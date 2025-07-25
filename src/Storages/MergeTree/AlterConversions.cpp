#include <Storages/MergeTree/AlterConversions.h>
#include <Storages/MergeTree/LoadedMergeTreeDataPartInfoForReader.h>
#include <Storages/MergeTree/MergeTreeRangeReader.h>
#include <Storages/MergeTree/MergeTreeVirtualColumns.h>
#include <Storages/MutationCommands.h>
#include <Interpreters/MutationsInterpreter.h>
#include <Interpreters/MutationsNonDeterministicHelpers.h>
#include <Parsers/ASTAlterQuery.h>
#include <Parsers/ASTAssignment.h>
#include <Parsers/ASTLiteral.h>
#include <Common/ProfileEvents.h>
#include <Core/Settings.h>
#include <ranges>

namespace ProfileEvents
{
    extern const Event ReadTasksWithAppliedPatches;
    extern const Event PatchesAppliedInAllReadTasks;
    extern const Event PatchesMergeAppliedInAllReadTasks;
    extern const Event PatchesJoinAppliedInAllReadTasks;
    extern const Event ReadTasksWithAppliedMutationsOnFly;
    extern const Event MutationsAppliedOnFlyInAllReadTasks;
}

namespace DB
{

namespace ErrorCodes
{
    extern const int BAD_ARGUMENTS;
    extern const int LOGICAL_ERROR;
    extern const int NOT_IMPLEMENTED;
}

/// Recreates ALTER UPDATE command but with assignment
/// list that contains only columns from @available_columns.
/// Example:
/// If we have mutation "UPDATE c1 = 'x', c2 = 'y' WHERE <cond>"
/// and we read only column "c1" in query then we need
/// to reacreate mutation command as "UPDATE c1 = 'x' WHERE <cond>"
static MutationCommand createCommandWithUpdatedColumns(
    const MutationCommand & command,
    std::unordered_map<String, ASTPtr> available_columns)
{
    chassert(command.type == MutationCommand::Type::UPDATE);
    chassert(command.ast);

    MutationCommand res;
    res.type = command.type;
    res.ast = command.ast->clone();

    if (command.predicate)
        res.predicate = command.predicate->clone();

    if (command.partition)
        res.partition = command.partition->clone();

    res.column_to_update_expression = std::move(available_columns);
    res.mutation_version = command.mutation_version;

    auto & alter_ast = assert_cast<ASTAlterCommand &>(*res.ast);
    auto new_assignments = std::make_shared<ASTExpressionList>();

    for (const auto & child : alter_ast.update_assignments->children)
    {
        const auto & assignment = assert_cast<const ASTAssignment &>(*child);
        if (res.column_to_update_expression.contains(assignment.column_name))
            new_assignments->children.push_back(child->clone());
    }

    alter_ast.update_assignments = alter_ast.children.emplace_back(std::move(new_assignments)).get();
    return res;
}

static bool isLightweightDeleteCommand(const String & column_name, const ASTPtr & ast)
{
    if (column_name != RowExistsColumn::name)
        return false;

    const auto * literal = ast->as<ASTLiteral>();
    if (!literal)
        return false;

    if (literal->value.getType() != Field::Types::UInt64)
        return false;

    return literal->value.safeGet<UInt64>() == 0;
}

static MutationCommand createLightweightDeleteCommand(const MutationCommand & command)
{
    chassert(command.type == MutationCommand::Type::UPDATE);
    chassert(command.predicate != nullptr);

    auto alter_command = std::make_shared<ASTAlterCommand>();
    alter_command->type = ASTAlterCommand::DELETE;

    if (command.partition)
        alter_command->partition = alter_command->children.emplace_back(command.partition->clone()).get();

    alter_command->predicate = alter_command->children.emplace_back(command.predicate->clone()).get();
    auto mutation_command = MutationCommand::parse(alter_command.get());

    if (!mutation_command)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Failed to parse command {}", alter_command->formatForErrorMessage());

    return *mutation_command;
}

AlterConversions::AlterConversions(
    const MutationCommands & mutation_commands_,
    const PatchPartsForReader & patch_parts_,
    const ContextPtr & context)
{
    for (const auto & command : mutation_commands_)
        addMutationCommand(command, context);

    for (const auto & patch : patch_parts_)
        addPatchPart(patch);

    /// Do not throw if there are no mutations or patches.
    if (number_of_alter_mutations > 1)
    {
        if (!mutation_commands.empty())
            throw Exception(ErrorCodes::NOT_IMPLEMENTED,
                "Applying mutations on-fly is not supported with more than one ALTER MODIFY");

        if (!patch_parts.empty())
            throw Exception(ErrorCodes::NOT_IMPLEMENTED,
                "Applying patch parts is not supported with more than one on-fly ALTER MODIFY");
    }
}

bool AlterConversions::hasLightweightDelete() const
{
    return all_updated_columns.contains(RowExistsColumn::name);
}

bool AlterConversions::isSupportedDataMutation(MutationCommand::Type type)
{
    return type == MutationCommand::UPDATE || type == MutationCommand::DELETE;
}

bool AlterConversions::isSupportedAlterMutation(MutationCommand::Type type)
{
    return type == MutationCommand::READ_COLUMN;
}

bool AlterConversions::isSupportedMetadataMutation(MutationCommand::Type type)
{
    return type == MutationCommand::RENAME_COLUMN;
}

void AlterConversions::addMutationCommand(const MutationCommand & command, const ContextPtr & context)
{
    using enum MutationCommand::Type;

    if (command.type == RENAME_COLUMN)
    {
        rename_map.emplace_back(RenamePair{command.rename_to, command.column_name});
    }
    else if (command.type == READ_COLUMN)
    {
        ++number_of_alter_mutations;
        version_of_alter_mutation = command.mutation_version;
    }
    else if (command.type == UPDATE || command.type == DELETE)
    {
        const auto result = findFirstNonDeterministicFunction(command, context);
        if (result.subquery)
            throw Exception(ErrorCodes::BAD_ARGUMENTS,
                "ALTER UPDATE/ALTER DELETE statement with subquery may be nondeterministic and cannot be applied on fly");

        if (result.nondeterministic_function_name)
            throw Exception(ErrorCodes::BAD_ARGUMENTS,
                "ALTER UPDATE/ALTER DELETE statements with nondeterministic deterministic functions cannot be applied on fly. "
                "Function '{}' is non-deterministic", *result.nondeterministic_function_name);

        for (const auto & [column, _] : command.column_to_update_expression)
            all_updated_columns.insert(column);

        mutation_commands.push_back(command);
    }
}

void AlterConversions::addPatchPart(PatchPartInfoForReader patch_part)
{
    for (const auto & column : patch_part.part->getColumns())
    {
        if (isPatchPartSystemColumn(column.name))
            continue;

        String updated_column_name = column.name;
        const auto & patch_conversions = patch_part.part->getAlterConversions();

        if (patch_conversions && patch_conversions->columnHasNewName(updated_column_name))
            updated_column_name = patch_conversions->getColumnNewName(column.name);

        all_updated_columns.insert(updated_column_name);
        columns_updated_in_patches.insert(updated_column_name);
    }

    /// For patches before ALTER MODIFY we should not apply conversions
    /// because correctness of ALTER MODIFY may depend on the data in patch part (the result of UPDATE).
    if (version_of_alter_mutation && !patchHasHigherDataVersion(*patch_part.part, *version_of_alter_mutation))
        patch_part.perform_alter_conversions = false;

    patch_parts.push_back(std::move(patch_part));
}

bool AlterConversions::columnHasNewName(const std::string & old_name) const
{
    for (const auto & [new_name, prev_name] : rename_map)
    {
        if (old_name == prev_name)
            return true;
    }

    return false;
}

std::string AlterConversions::getColumnNewName(const std::string & old_name) const
{
    for (const auto & [new_name, prev_name] : rename_map)
    {
        if (old_name == prev_name)
            return new_name;
    }

    throw Exception(ErrorCodes::LOGICAL_ERROR, "Column {} was not renamed", old_name);
}

bool AlterConversions::isColumnRenamed(const std::string & new_name) const
{
    for (const auto & [name_to, name_from] : rename_map)
    {
        if (name_to == new_name)
            return true;
    }
    return false;
}

/// Get column old name before rename (lookup by key in rename_map)
std::string AlterConversions::getColumnOldName(const std::string & new_name) const
{
    for (const auto & [name_to, name_from] : rename_map)
    {
        if (name_to == new_name)
            return name_from;
    }
    throw Exception(ErrorCodes::LOGICAL_ERROR, "Column {} was not renamed", new_name);
}

PrewhereExprSteps AlterConversions::getMutationSteps(
    const IMergeTreeDataPartInfoForReader & part_info,
    const NamesAndTypesList & read_columns,
    const StorageMetadataPtr & metadata_snapshot,
    const ContextPtr & context) const
{
    auto actions_chain = getMutationActions(part_info, read_columns, metadata_snapshot, context);
    auto settings = ExpressionActionsSettings(context);

    PrewhereExprSteps steps;
    for (auto & actions : actions_chain)
    {
        /// For mutations before ALTER MODIFY we should not apply conversions
        /// because correctness of ALTER MODIFY may depend on the result of mutation.
        bool perform_alter_conversions = !version_of_alter_mutation || actions.mutation_version > version_of_alter_mutation;
        bool is_filter = !actions.filter_column_name.empty();

        PrewhereExprStep step
        {
            .type = is_filter ? PrewhereExprStep::Filter : PrewhereExprStep::Expression,
            .actions = std::make_shared<ExpressionActions>(std::move(actions.dag), settings, actions.project_input),
            .filter_column_name = actions.filter_column_name,
            .remove_filter_column = false,
            .need_filter = is_filter,
            .perform_alter_conversions = perform_alter_conversions,
            .mutation_version = actions.mutation_version,
        };

        steps.push_back(std::make_shared<PrewhereExprStep>(std::move(step)));
    }

    return steps;
}

PatchPartsForReader AlterConversions::getPatchesForColumns(const NamesAndTypesList & read_columns, bool apply_deleted_mask) const
{
    PatchPartsForReader patches_to_read;

    size_t num_join = 0;
    size_t num_merge = 0;

    for (const auto & patch : patch_parts)
    {
        bool has_column_in_patch;
        const auto & patch_conversions = patch.part->getAlterConversions();

        /// If patch has lightweight delete we have to always apply it.
        if (apply_deleted_mask && patch.part->hasLightweightDelete())
        {
            has_column_in_patch = true;
        }
        else
        {
            has_column_in_patch = std::ranges::any_of(read_columns, [&](const auto & column)
            {
                if (isPatchPartSystemColumn(column.name))
                    return false;

                auto name_in_storage = column.getNameInStorage();

                if (patch_conversions && patch_conversions->isColumnRenamed(name_in_storage))
                    name_in_storage = patch_conversions->getColumnOldName(name_in_storage);

                return patch.part->getColumnsDescription().hasPhysical(name_in_storage);
            });
        }

        if (has_column_in_patch)
        {
            if (patch.mode == PatchMode::Join)
                ++num_join;
            else
                ++num_merge;

            patches_to_read.push_back(patch);
        }
    }

    if (!patches_to_read.empty())
    {
        ProfileEvents::increment(ProfileEvents::ReadTasksWithAppliedPatches);
        ProfileEvents::increment(ProfileEvents::PatchesAppliedInAllReadTasks, patches_to_read.size());
        ProfileEvents::increment(ProfileEvents::PatchesJoinAppliedInAllReadTasks, num_join);
        ProfileEvents::increment(ProfileEvents::PatchesMergeAppliedInAllReadTasks, num_merge);
    }

    return patches_to_read;
}

std::vector<MutationActions> AlterConversions::getMutationActions(
    const IMergeTreeDataPartInfoForReader & part_info,
    const NamesAndTypesList & read_columns,
    const StorageMetadataPtr & metadata_snapshot,
    const ContextPtr & context) const
{
    if (mutation_commands.empty())
        return {};

    const auto * loaded_part_info = dynamic_cast<const LoadedMergeTreeDataPartInfoForReader *>(&part_info);
    if (!loaded_part_info)
        throw Exception(ErrorCodes::NOT_IMPLEMENTED,
            "Applying mutations on-fly is supported only for loaded data parts");

    Names storage_read_columns;
    NameSet storage_read_columns_set;

    for (const auto & column : read_columns)
    {
        auto name_in_storage = column.getNameInStorage();
        if (storage_read_columns_set.emplace(name_in_storage).second)
            storage_read_columns.emplace_back(name_in_storage);
    }

    addColumnsRequiredForMaterialized(storage_read_columns, storage_read_columns_set, metadata_snapshot, context);
    auto filtered_commands = filterMutationCommands(storage_read_columns, std::move(storage_read_columns_set));

    if (filtered_commands.empty())
        return {};

    ProfileEvents::increment(ProfileEvents::ReadTasksWithAppliedMutationsOnFly);
    ProfileEvents::increment(ProfileEvents::MutationsAppliedOnFlyInAllReadTasks, filtered_commands.size());

    MutationsInterpreter::Settings settings(true);
    settings.return_all_columns = true;
    settings.recalculate_dependencies_of_updated_columns = false;

    const auto & part = loaded_part_info->getDataPart();
    auto alter_conversions = std::make_shared<AlterConversions>();

    MutationsInterpreter interpreter(
        const_cast<MergeTreeData &>(part->storage),
        part,
        alter_conversions,
        metadata_snapshot,
        std::move(filtered_commands),
        std::move(storage_read_columns),
        context,
        settings);

    return interpreter.getMutationActions();
}

void AlterConversions::addColumnsRequiredForMaterialized(
    Names & read_columns,
    NameSet & read_columns_set,
    const StorageMetadataPtr & metadata_snapshot,
    const ContextPtr & context) const
{
    NameSet required_source_columns;
    const auto & columns_desc = metadata_snapshot->getColumns();
    auto source_columns = metadata_snapshot->getColumns().getAllPhysical();

    for (const auto & column_name : read_columns_set)
    {
        auto default_desc = columns_desc.getDefault(column_name);
        if (default_desc && default_desc->kind == ColumnDefaultKind::Materialized)
        {
            auto query = default_desc->expression->clone();
            auto syntax_result = TreeRewriter(context).analyze(query, source_columns);

            for (const auto & dependency : syntax_result->requiredSourceColumns())
            {
                if (all_updated_columns.contains(dependency))
                    required_source_columns.insert(dependency);
            }
        }
    }

    for (const auto & column_name : required_source_columns)
    {
        if (read_columns_set.emplace(column_name).second)
            read_columns.push_back(column_name);
    }
}

MutationCommands AlterConversions::filterMutationCommands(Names & read_columns, NameSet read_columns_set) const
{
    MutationCommands filtered_commands;

    /// We need to read all columns that are used in mutation.
    /// Therefore we need to add all previous mutations that affects such columns.
    /// Because of that we iterate over commands backwards.
    for (const auto & command : mutation_commands | std::views::reverse)
    {
        IdentifierNameSet source_columns;
        if (command.type == MutationCommand::Type::DELETE)
        {
            command.predicate->collectIdentifierNames(source_columns);
            filtered_commands.push_back(command);
        }
        else if (command.type == MutationCommand::Type::UPDATE)
        {
            bool has_lightweight_delete = false;
            std::unordered_map<String, ASTPtr> new_updated_columns;

            for (const auto & [column, ast] : command.column_to_update_expression)
            {
                if (isLightweightDeleteCommand(column, ast))
                {
                    has_lightweight_delete = true;
                }
                else if (read_columns_set.contains(column))
                {
                    ast->collectIdentifierNames(source_columns);
                    new_updated_columns.emplace(column, ast->clone());
                }
            }

            if (has_lightweight_delete)
            {
                auto new_command = createLightweightDeleteCommand(command);
                new_command.predicate->collectIdentifierNames(source_columns);
                filtered_commands.push_back(std::move(new_command));
            }

            if (!new_updated_columns.empty())
            {
                auto new_command = createCommandWithUpdatedColumns(command, std::move(new_updated_columns));
                new_command.predicate->collectIdentifierNames(source_columns);
                filtered_commands.push_back(std::move(new_command));
            }
        }
        else
        {
            throw Exception(ErrorCodes::LOGICAL_ERROR,
                "Unexpected mutation of type {} in AlterConversions. Only UPDATE and DELETE mutations are supported",
                magic_enum::enum_name(command.type));
        }

        for (const auto & column : source_columns)
        {
            if (read_columns_set.emplace(column).second)
                read_columns.push_back(column);
        }
    }

    std::reverse(filtered_commands.begin(), filtered_commands.end());
    return filtered_commands;
}

void MutationCounters::assertNotNegative() const
{
    if (num_data < 0)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "On-fly data mutations counter is negative ({})", num_data);

    if (num_alter < 0)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "On-fly alter mutations counter is negative ({})", num_alter);

    if (num_metadata < 0)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "On-fly metadata mutations counter is negative ({})", num_metadata);
}

}

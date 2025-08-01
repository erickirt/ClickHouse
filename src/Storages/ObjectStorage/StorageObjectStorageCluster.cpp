#include <Storages/ObjectStorage/StorageObjectStorageCluster.h>

#include <Common/Exception.h>
#include <Common/StringUtils.h>
#include <Parsers/ASTSetQuery.h>
#include <Interpreters/Context.h>

#include <Core/Settings.h>
#include <Formats/FormatFactory.h>
#include <Processors/Sources/RemoteSource.h>
#include <QueryPipeline/RemoteQueryExecutor.h>
#include <Storages/IPartitionStrategy.h>

#include <Storages/VirtualColumnUtils.h>
#include <Storages/HivePartitioningUtils.h>
#include <Storages/ObjectStorage/Utils.h>
#include <Storages/ObjectStorage/StorageObjectStorageSource.h>
#include <Storages/extractTableFunctionFromSelectQuery.h>
#include <Storages/ObjectStorage/StorageObjectStorageStableTaskDistributor.h>


namespace DB
{
namespace Setting
{
    extern const SettingsBool use_hive_partitioning;
    extern const SettingsBool cluster_function_process_archive_on_multiple_nodes;
}

namespace ErrorCodes
{
    extern const int LOGICAL_ERROR;
    extern const int INCORRECT_DATA;
}

String StorageObjectStorageCluster::getPathSample(ContextPtr context)
{
    auto query_settings = configuration->getQuerySettings(context);
    /// We don't want to throw an exception if there are no files with specified path.
    query_settings.throw_on_zero_files_match = false;
    auto file_iterator = StorageObjectStorageSource::createFileIterator(
        configuration,
        query_settings,
        object_storage,
        false, // distributed_processing
        context,
        {}, // predicate
        {},
        {}, // virtual_columns
        {}, // hive_columns
        nullptr, // read_keys
        {} // file_progress_callback
    );

    if (auto file = file_iterator->next(0))
        return file->getPath();
    return "";
}

StorageObjectStorageCluster::StorageObjectStorageCluster(
    const String & cluster_name_,
    StorageObjectStorageConfigurationPtr configuration_,
    ObjectStoragePtr object_storage_,
    const StorageID & table_id_,
    const ColumnsDescription & columns_in_table_or_function_definition,
    const ConstraintsDescription & constraints_,
    const ASTPtr & partition_by,
    ContextPtr context_)
    : IStorageCluster(
        cluster_name_, table_id_, getLogger(fmt::format("{}({})", configuration_->getEngineName(), table_id_.table_name)))
    , configuration{configuration_}
    , object_storage(object_storage_)
{
    configuration->initPartitionStrategy(partition_by, columns_in_table_or_function_definition, context_);
    /// We allow exceptions to be thrown on update(),
    /// because Cluster engine can only be used as table function,
    /// so no lazy initialization is allowed.
    configuration->update(
        object_storage,
        context_,
        /* if_not_updated_before */false,
        /* check_consistent_with_previous_metadata */true);

    ColumnsDescription columns{columns_in_table_or_function_definition};
    std::string sample_path;
    resolveSchemaAndFormat(columns, configuration->format, object_storage, configuration, {}, sample_path, context_);
    configuration->check(context_);

    if (sample_path.empty() && context_->getSettingsRef()[Setting::use_hive_partitioning] && !configuration->isDataLakeConfiguration() && !configuration->partition_strategy)
        sample_path = getPathSample(context_);

    /*
     * If `partition_strategy=hive`, the partition columns shall be extracted from the `PARTITION BY` expression.
     * There is no need to read from the filepath.
     *
     * Otherwise, in case `use_hive_partitioning=1`, we can keep the old behavior of extracting it from the sample path.
     * And if the schema was inferred (not specified in the table definition), we need to enrich it with the path partition columns
     */
    if (configuration->partition_strategy && configuration->partition_strategy_type == PartitionStrategyFactory::StrategyType::HIVE)
    {
        hive_partition_columns_to_read_from_file_path = configuration->partition_strategy->getPartitionColumns();
    }
    else if (context_->getSettingsRef()[Setting::use_hive_partitioning])
    {
        HivePartitioningUtils::extractPartitionColumnsFromPathAndEnrichStorageColumns(
            columns,
            hive_partition_columns_to_read_from_file_path,
            sample_path,
            columns_in_table_or_function_definition.empty(),
            std::nullopt,
            context_
        );
    }

    if (hive_partition_columns_to_read_from_file_path.size() == columns.size())
    {
        throw Exception(
            ErrorCodes::INCORRECT_DATA,
            "A hive partitioned file can't contain only partition columns. Try reading it with `partition_strategy=wildcard` and `use_hive_partitioning=0`");
    }

    /// Hive: Not building the file_columns like `StorageObjectStorage` does because it is not necessary to do it here.

    StorageInMemoryMetadata metadata;
    metadata.setColumns(columns);
    metadata.setConstraints(constraints_);

    setVirtuals(VirtualColumnUtils::getVirtualsForFileLikeStorage(metadata.columns));
    setInMemoryMetadata(metadata);
}

std::string StorageObjectStorageCluster::getName() const
{
    return configuration->getEngineName();
}

std::optional<UInt64> StorageObjectStorageCluster::totalRows(ContextPtr query_context) const
{
    configuration->update(
        object_storage,
        query_context,
        /* if_not_updated_before */false,
        /* check_consistent_with_previous_metadata */true);
    return configuration->totalRows(query_context);
}

std::optional<UInt64> StorageObjectStorageCluster::totalBytes(ContextPtr query_context) const
{
    configuration->update(
        object_storage,
        query_context,
        /* if_not_updated_before */false,
        /* check_consistent_with_previous_metadata */true);
    return configuration->totalBytes(query_context);
}

void StorageObjectStorageCluster::updateQueryToSendIfNeeded(
    ASTPtr & query,
    const DB::StorageSnapshotPtr & storage_snapshot,
    const ContextPtr & context)
{
    auto * table_function = extractTableFunctionFromSelectQuery(query);
    if (!table_function)
    {
        throw Exception(
            ErrorCodes::LOGICAL_ERROR,
            "Expected SELECT query from table function {}, got '{}'",
            configuration->getEngineName(), query->formatForErrorMessage());
    }

    auto * expression_list = table_function->arguments->as<ASTExpressionList>();
    if (!expression_list)
    {
        throw Exception(
            ErrorCodes::LOGICAL_ERROR,
            "Expected SELECT query from table function {}, got '{}'",
            configuration->getEngineName(), query->formatForErrorMessage());
    }

    ASTs & args = expression_list->children;
    const auto & structure = storage_snapshot->metadata->getColumns().getAll().toNamesAndTypesDescription();
    if (args.empty())
    {
        throw Exception(
            ErrorCodes::LOGICAL_ERROR,
            "Unexpected empty list of arguments for {}Cluster table function",
            configuration->getEngineName());
    }

    ASTPtr settings_temporary_storage = nullptr;
    for (auto * it = args.begin(); it != args.end(); ++it)
    {
        ASTSetQuery * settings_ast = (*it)->as<ASTSetQuery>();
        if (settings_ast)
        {
            settings_temporary_storage = std::move(*it);
            args.erase(it);
            break;
        }
    }

    if (!endsWith(table_function->name, "Cluster"))
        configuration->addStructureAndFormatToArgsIfNeeded(args, structure, configuration->format, context, /*with_structure=*/true);
    else
    {
        ASTPtr cluster_name_arg = args.front();
        args.erase(args.begin());
        configuration->addStructureAndFormatToArgsIfNeeded(args, structure, configuration->format, context, /*with_structure=*/true);
        args.insert(args.begin(), cluster_name_arg);
    }
    if (settings_temporary_storage)
    {
        args.insert(args.end(), std::move(settings_temporary_storage));
    }
}


RemoteQueryExecutor::Extension StorageObjectStorageCluster::getTaskIteratorExtension(
    const ActionsDAG::Node * predicate,
    const ActionsDAG * filter,
    const ContextPtr & local_context,
    const size_t number_of_replicas) const
{
    auto iterator = StorageObjectStorageSource::createFileIterator(
        configuration,
        configuration->getQuerySettings(local_context),
        object_storage,
        /* distributed_processing */false,
        local_context,
        predicate,
        filter,
        virtual_columns,
        hive_partition_columns_to_read_from_file_path,
        nullptr,
        local_context->getFileProgressCallback(),
        /*ignore_archive_globs=*/false,
        /*skip_object_metadata=*/true);

    auto task_distributor = std::make_shared<StorageObjectStorageStableTaskDistributor>(
        iterator,
        number_of_replicas,
        /* send_over_whole_archive */!local_context->getSettingsRef()[Setting::cluster_function_process_archive_on_multiple_nodes]);

    auto callback = std::make_shared<TaskIterator>(
        [task_distributor, local_context](size_t number_of_current_replica) mutable -> ClusterFunctionReadTaskResponsePtr
        {
            auto task = task_distributor->getNextTask(number_of_current_replica);
            if (task)
                return std::make_shared<ClusterFunctionReadTaskResponse>(std::move(task), local_context);
            return std::make_shared<ClusterFunctionReadTaskResponse>();
        });

    return RemoteQueryExecutor::Extension{.task_iterator = std::move(callback)};
}

}

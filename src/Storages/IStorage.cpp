#include <Storages/IStorage.h>

#include <Disks/IStoragePolicy.h>
#include <Common/StringUtils.h>
#include <Core/Settings.h>
#include <IO/Operators.h>
#include <IO/WriteBufferFromString.h>
#include <Interpreters/Context.h>
#include <Interpreters/DatabaseCatalog.h>
#include <Interpreters/InterpreterSelectQuery.h>
#include <Parsers/ASTCreateQuery.h>
#include <QueryPipeline/Pipe.h>
#include <Processors/QueryPlan/ReadFromPreparedSource.h>
#include <Processors/QueryPlan/QueryPlan.h>
#include <Storages/AlterCommands.h>
#include <Storages/Statistics/ConditionSelectivityEstimator.h>
#include <Backups/RestorerFromBackup.h>
#include <Backups/IBackup.h>


namespace DB
{
namespace Setting
{
    extern const SettingsBool parallelize_output_from_storages;
    extern const SettingsBool distributed_aggregation_memory_efficient;
}

namespace ErrorCodes
{
    extern const int TABLE_IS_DROPPED;
    extern const int NOT_IMPLEMENTED;
    extern const int DEADLOCK_AVOIDED;
    extern const int CANNOT_RESTORE_TABLE;
    extern const int TABLE_IS_BEING_RESTARTED;
}

const VirtualColumnsDescription IStorage::common_virtuals = IStorage::createCommonVirtuals();

IStorage::IStorage(StorageID storage_id_, std::unique_ptr<StorageInMemoryMetadata> metadata_)
    : storage_id(std::move(storage_id_))
    , virtuals(std::make_unique<VirtualColumnsDescription>())
{
    if (metadata_)
        metadata.set(std::move(metadata_));
    else
        metadata.set(std::make_unique<StorageInMemoryMetadata>());
}

bool IStorage::isVirtualColumn(const String & column_name, const StorageMetadataPtr & metadata_snapshot) const
{
    /// Virtual column maybe overridden by real column
    return !metadata_snapshot->getColumns().has(column_name) && (virtuals.get()->has(column_name) || common_virtuals.has(column_name));
}

VirtualColumnsDescription IStorage::createCommonVirtuals()
{
    VirtualColumnsDescription desc;

    desc.addEphemeral("_table", std::make_shared<DataTypeLowCardinality>(std::make_shared<DataTypeString>()), "The name of table which the row comes from");

    return desc;
}

RWLockImpl::LockHolder IStorage::tryLockTimed(
    const RWLock & rwlock, RWLockImpl::Type type, const String & query_id, const std::chrono::milliseconds & acquire_timeout) const
{
    auto lock_holder = rwlock->getLock(type, query_id, acquire_timeout);
    if (!lock_holder)
    {
        const String type_str = type == RWLockImpl::Type::Read ? "READ" : "WRITE";
        throw Exception(ErrorCodes::DEADLOCK_AVOIDED,
            "{} locking attempt on \"{}\" has timed out! ({}ms) Possible deadlock avoided. Client should retry. Owner query ids: {}",
            type_str, getStorageID(), acquire_timeout.count(), rwlock->getOwnerQueryIdsDescription());
    }
    return lock_holder;
}

TableLockHolder IStorage::lockForShare(const String & query_id, const std::chrono::milliseconds & acquire_timeout)
{
    TableLockHolder result = tryLockTimed(drop_lock, RWLockImpl::Read, query_id, acquire_timeout);
    auto table_id = getStorageID();
    if (!table_id.hasUUID() && (is_dropped || is_detached))
        throw Exception(ErrorCodes::TABLE_IS_DROPPED, "Table {}.{} is dropped or detached", table_id.database_name, table_id.table_name);

    if (is_being_restarted)
        throw Exception(
            ErrorCodes::TABLE_IS_BEING_RESTARTED, "Table {}.{} is being restarted", table_id.database_name, table_id.table_name);
    return result;
}

TableLockHolder IStorage::tryLockForShare(const String & query_id, const std::chrono::milliseconds & acquire_timeout)
{
    TableLockHolder result = tryLockTimed(drop_lock, RWLockImpl::Read, query_id, acquire_timeout);

    auto table_id = getStorageID();
    if (is_being_restarted || (!table_id.hasUUID() && (is_dropped || is_detached)))
        // Table was dropped or is being restarted while acquiring the lock
        result = nullptr;
    return result;
}

std::optional<IStorage::AlterLockHolder> IStorage::tryLockForAlter(const std::chrono::milliseconds & acquire_timeout)
{
    AlterLockHolder lock{alter_lock, std::defer_lock};

    if (!lock.try_lock_for(acquire_timeout))
        return {};

    if (is_dropped || is_detached)
        throw Exception(ErrorCodes::TABLE_IS_DROPPED, "Table {} is dropped or detached", getStorageID());

    return lock;
}

IStorage::AlterLockHolder IStorage::lockForAlter(const std::chrono::milliseconds & acquire_timeout)
{
    auto lock = tryLockForAlter(acquire_timeout);
    if (lock == std::nullopt)
        throw Exception(ErrorCodes::DEADLOCK_AVOIDED,
                        "Locking attempt for ALTER on \"{}\" has timed out! ({} ms) "
                        "Possible deadlock avoided. Client should retry.",
                        getStorageID().getFullTableName(), acquire_timeout.count());
    return std::move(*lock);
}


TableExclusiveLockHolder IStorage::lockExclusively(const String & query_id, const std::chrono::milliseconds & acquire_timeout)
{
    TableExclusiveLockHolder result;
    result.drop_lock = tryLockTimed(drop_lock, RWLockImpl::Write, query_id, acquire_timeout);

    if (is_dropped || is_detached)
        throw Exception(ErrorCodes::TABLE_IS_DROPPED, "Table {} is dropped or detached", getStorageID());

    return result;
}

Pipe IStorage::watch(
    const Names & /*column_names*/,
    const SelectQueryInfo & /*query_info*/,
    ContextPtr /*context*/,
    QueryProcessingStage::Enum & /*processed_stage*/,
    size_t /*max_block_size*/,
    size_t /*num_streams*/)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Method watch is not supported by storage {}", getName());
}

Pipe IStorage::read(
    const Names & /*column_names*/,
    const StorageSnapshotPtr & /*storage_snapshot*/,
    SelectQueryInfo & /*query_info*/,
    ContextPtr /*context*/,
    QueryProcessingStage::Enum /*processed_stage*/,
    size_t /*max_block_size*/,
    size_t /*num_streams*/)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Method read is not supported by storage {}", getName());
}

SinkToStoragePtr IStorage::write(
    const ASTPtr & /*query*/,
    const StorageMetadataPtr & /*metadata_snapshot*/,
    ContextPtr /*context*/,
    bool /*async_insert*/)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Method write is not supported by storage {}", getName());
}

void IStorage::truncate(
    const ASTPtr & /*query*/,
    const StorageMetadataPtr & /* metadata_snapshot */,
    ContextPtr /* context */,
    TableExclusiveLockHolder &)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Truncate is not supported by storage {}", getName());
}

void IStorage::read(
    QueryPlan & query_plan,
    const Names & column_names,
    const StorageSnapshotPtr & storage_snapshot,
    SelectQueryInfo & query_info,
    ContextPtr context,
    QueryProcessingStage::Enum processed_stage,
    size_t max_block_size,
    size_t num_streams)
{
    auto pipe = read(column_names, storage_snapshot, query_info, context, processed_stage, max_block_size, num_streams);

    /// parallelize processing if not yet
    const size_t output_ports = pipe.numOutputPorts();
    const bool parallelize_output = context->getSettingsRef()[Setting::parallelize_output_from_storages];

    /// For distributed_aggregation_memory_efficient with Two-Level-Hash aggregation, the `GroupingAggregatedTransform`
    /// need to receive buckets from Remote in order of bucket number, while resize here will break the buckets order
    /// return from `RemoteSource`. See https://github.com/ClickHouse/ClickHouse/issues/76934.
    const bool should_not_resize = context->getSettingsRef()[Setting::distributed_aggregation_memory_efficient]
        && processed_stage == QueryProcessingStage::Enum::WithMergeableState;

    if (!should_not_resize && parallelize_output && parallelizeOutputAfterReading(context) && output_ports > 0
        && output_ports < num_streams)
        pipe.resize(num_streams);

    readFromPipe(query_plan, std::move(pipe), column_names, storage_snapshot, query_info, context, shared_from_this());
}

void IStorage::readFromPipe(
    QueryPlan & query_plan,
    Pipe pipe,
    const Names & column_names,
    const StorageSnapshotPtr & storage_snapshot,
    SelectQueryInfo & query_info,
    ContextPtr context,
    std::shared_ptr<IStorage> storage_)
{
    if (pipe.empty())
    {
        auto header = storage_snapshot->getSampleBlockForColumns(column_names);
        InterpreterSelectQuery::addEmptySourceToQueryPlan(query_plan, header, query_info);
    }
    else
    {
        auto read_step = std::make_unique<ReadFromStorageStep>(std::move(pipe), storage_, context, query_info);
        query_plan.addStep(std::move(read_step));
    }
}

std::optional<QueryPipeline> IStorage::distributedWrite(
    const ASTInsertQuery & /*query*/,
    ContextPtr /*context*/)
{
    return {};
}

Pipe IStorage::alterPartition(
    const StorageMetadataPtr & /* metadata_snapshot */, const PartitionCommands & /* commands */, ContextPtr /* context */)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Partition operations are not supported by storage {}", getName());
}

void IStorage::alter(const AlterCommands & params, ContextPtr context, AlterLockHolder &)
{
    auto table_id = getStorageID();
    StorageInMemoryMetadata new_metadata = getInMemoryMetadata();
    params.apply(new_metadata, context);
    DatabaseCatalog::instance().getDatabase(table_id.database_name)->alterTable(context, table_id, new_metadata);
    setInMemoryMetadata(new_metadata);
}

void IStorage::checkAlterIsPossible(const AlterCommands & commands, ContextPtr /* context */) const
{
    for (const auto & command : commands)
    {
        if (!command.isCommentAlter())
            throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Alter of type '{}' is not supported by storage {}",
                command.type, getName());
    }
}

void IStorage::checkMutationIsPossible(const MutationCommands & /*commands*/, const Settings & /*settings*/) const
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Table engine {} doesn't support mutations", getName());
}

void IStorage::checkAlterPartitionIsPossible(
    const PartitionCommands & /*commands*/,
    const StorageMetadataPtr & /*metadata_snapshot*/,
    const Settings & /*settings*/,
    ContextPtr /*context*/) const
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Table engine {} doesn't support partitioning", getName());
}

bool IStorage::optimize(
        const ASTPtr & /*query*/,
        const StorageMetadataPtr & /*metadata_snapshot*/,
        const ASTPtr & /*partition*/,
        bool /*final*/,
        bool /*deduplicate*/,
        const Names & /* deduplicate_by_columns */,
        bool /*cleanup*/,
        ContextPtr /*context*/)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Method optimize is not supported by storage {}", getName());
}

std::expected<void, PreformattedMessage> IStorage::supportsLightweightUpdate() const
{
    return std::unexpected(PreformattedMessage::create("Table with engine {} doesn't support lightweight updates", getName()));
}

QueryPipeline IStorage::updateLightweight(const MutationCommands &, ContextPtr)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Lightweight updates are not supported by storage {}", getName());
}

void IStorage::mutate(const MutationCommands &, ContextPtr)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Mutations are not supported by storage {}", getName());
}

CancellationCode IStorage::killMutation(const String & /*mutation_id*/)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Mutations are not supported by storage {}", getName());
}

void IStorage::waitForMutation(const String & /*mutation_id*/, bool /*wait_for_another_mutation*/)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Mutations are not supported by storage {}", getName());
}

void IStorage::setMutationCSN(const String & /*mutation_id*/, UInt64 /*csn*/)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Mutations are not supported by storage {}", getName());
}

CancellationCode IStorage::killPartMoveToShard(const UUID & /*task_uuid*/)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Part moves between shards are not supported by storage {}", getName());
}

StorageID IStorage::getStorageID() const
{
    std::lock_guard lock(id_mutex);
    return storage_id;
}

ConditionSelectivityEstimator IStorage::getConditionSelectivityEstimatorByPredicate(const StorageSnapshotPtr &, const ActionsDAG *, ContextPtr) const
{
    return {};
}

void IStorage::renameInMemory(const StorageID & new_table_id)
{
    std::lock_guard lock(id_mutex);
    storage_id = new_table_id;
}

Names IStorage::getAllRegisteredNames() const
{
    Names result;
    auto getter = [](const auto & column) { return column.name; };
    const NamesAndTypesList & available_columns = getInMemoryMetadata().getColumns().getAllPhysical();
    std::transform(available_columns.begin(), available_columns.end(), std::back_inserter(result), getter);
    return result;
}

NameDependencies IStorage::getDependentViewsByColumn(ContextPtr context) const
{
    NameDependencies name_deps;
    auto view_ids = DatabaseCatalog::instance().getDependentViews(storage_id);
    for (const auto & view_id : view_ids)
    {
        auto view = DatabaseCatalog::instance().getTable(view_id, context);
        if (view->getInMemoryMetadataPtr()->select.inner_query)
        {
            const auto & select_query = view->getInMemoryMetadataPtr()->select.inner_query;
            auto required_columns = InterpreterSelectQuery(select_query, context, SelectQueryOptions{}.noModify()).getRequiredColumns();
            for (const auto & col_name : required_columns)
                name_deps[col_name].push_back(view_id.table_name);
        }
    }
    return name_deps;
}

bool IStorage::isStaticStorage() const
{
    auto storage_policy = getStoragePolicy();
    if (storage_policy)
    {
        for (const auto & disk : storage_policy->getDisks())
            if (!(disk->isReadOnly() || disk->isWriteOnce()))
                return false;
        return true;
    }
    return false;
}

IStorage::DataValidationTasksPtr IStorage::getCheckTaskList(const CheckTaskFilter &, ContextPtr)
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "Check query is not supported for {} storage", getName());
}

std::optional<CheckResult> IStorage::checkDataNext(DataValidationTasksPtr & /* check_task_list */)
{
    return {};
}

void IStorage::applyMetadataChangesToCreateQueryForBackup(ASTPtr &) const
{
}

void IStorage::backupData(BackupEntriesCollector &, const String &, const std::optional<ASTs> &)
{
}

void IStorage::restoreDataFromBackup(RestorerFromBackup & restorer, const String & data_path_in_backup, const std::optional<ASTs> &)
{
    /// If an inherited class doesn't override restoreDataFromBackup() that means it doesn't backup any data.
    auto filenames = restorer.getBackup()->listFiles(data_path_in_backup, /*recursive*/ false);
    if (!filenames.empty())
        throw Exception(ErrorCodes::CANNOT_RESTORE_TABLE, "Cannot restore table {}: Folder {} in backup must be empty",
                        getStorageID().getFullTableName(), data_path_in_backup);
}

std::string PrewhereInfo::dump() const
{
    WriteBufferFromOwnString ss;
    ss << "PrewhereDagInfo\n";

    if (row_level_filter)
    {
        ss << "row_level_filter " << row_level_filter->dumpDAG() << "\n";
    }

    {
        ss << "prewhere_actions " << prewhere_actions.dumpDAG() << "\n";
    }

    ss << "remove_prewhere_column " << remove_prewhere_column
       << ", need_filter " << need_filter << "\n";

    return ss.str();
}

std::string FilterDAGInfo::dump() const
{
    WriteBufferFromOwnString ss;
    ss << "FilterDAGInfo for column '" << column_name <<"', do_remove_column "
       << do_remove_column << "\n";

    ss << "actions " << actions.dumpDAG() << "\n";

    return ss.str();
}

}

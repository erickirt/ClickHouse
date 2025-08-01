#pragma once

#include "config.h"

#if USE_DELTA_KERNEL_RS

#include <Core/Types.h>
#include <IO/S3/URI.h>
#include <Common/Logger.h>
#include <Storages/ObjectStorage/StorageObjectStorage.h>
#include <Storages/ObjectStorage/IObjectIterator.h>
#include <Storages/ObjectStorage/DataLakes/IDataLakeMetadata.h>
#include <Storages/ObjectStorage/DataLakes/DeltaLake/KernelPointerWrapper.h>
#include <Storages/ObjectStorage/DataLakes/DeltaLake/KernelHelper.h>
#include <boost/noncopyable.hpp>
#include "delta_kernel_ffi.hpp"

namespace DeltaLake
{

/**
 * A class representing DeltaLake table snapshot -
 * a snapshot of table state, its schema, data files, etc.
 */
class TableSnapshot
{
public:
    explicit TableSnapshot(
        KernelHelperPtr helper_,
        DB::ObjectStoragePtr object_storage_,
        DB::ContextPtr context_,
        LoggerPtr log_);

    /// Get snapshot version.
    size_t getVersion() const;

    /// Update snapshot to latest version.
    bool update();

    /// Iterate over DeltaLake data files.
    DB::ObjectIterator iterate(
        const DB::ActionsDAG * filter_dag,
        DB::IDataLakeMetadata::FileProgressCallback callback,
        size_t list_batch_size);

    /// Get schema from DeltaLake table metadata.
    const DB::NamesAndTypesList & getTableSchema() const;
    /// Get read schema derived from data files.
    /// (In most cases it would be the same as table schema).
    const DB::NamesAndTypesList & getReadSchema() const;
    /// DeltaLake stores partition columns values not in the data files,
    /// but in data file path directory names.
    /// Therefore "table schema" would contain partition columns,
    /// but "read schema" would not.
    const DB::Names & getPartitionColumns() const;
    const DB::NameToNameMap & getPhysicalNamesMap() const;

private:
    class Iterator;
    using KernelExternEngine = KernelPointerWrapper<ffi::SharedExternEngine, ffi::free_engine>;
    using KernelSnapshot = KernelPointerWrapper<ffi::SharedSnapshot, ffi::free_snapshot>;
    using KernelScan = KernelPointerWrapper<ffi::SharedScan, ffi::free_scan>;

    const KernelHelperPtr helper;
    const DB::ObjectStoragePtr object_storage;
    const LoggerPtr log;
    const bool enable_expression_visitor_logging;

    mutable KernelExternEngine engine;
    mutable KernelSnapshot snapshot;
    mutable KernelScan scan;
    mutable size_t snapshot_version;

    using TableSchema = DB::NamesAndTypesList;
    using ReadSchema = DB::NamesAndTypesList;

    mutable TableSchema table_schema;
    mutable ReadSchema read_schema;
    mutable DB::NameToNameMap physical_names_map;
    mutable DB::Names partition_columns;

    void initSnapshot() const;
    void initSnapshotImpl() const;
};

/// TODO; Enable event tracing in DeltaKernel.

}

#endif

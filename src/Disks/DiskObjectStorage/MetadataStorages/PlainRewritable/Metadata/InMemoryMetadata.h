#pragma once

#include <Disks/DiskObjectStorage/MetadataStorages/PlainRewritable/Metadata/DirectoryTree.h>

#include <Common/CurrentMetrics.h>

#include <base/defines.h>

namespace DB
{

class InMemoryMetadata
{
public:
    InMemoryMetadata(CurrentMetrics::Metric metric_directories_name, CurrentMetrics::Metric metric_files_name);

    void applySnapshot(std::shared_ptr<DirectoryTree> snapshot);
    void applyLayout(std::unordered_map<std::string, DirectoryRemoteInfo> remote_layout);

    std::shared_ptr<DirectoryTree> takeSnapshot() const;
    std::shared_ptr<const DirectoryTree> takeReadSnapshot() const;

private:
    mutable std::mutex mutex;
    std::shared_ptr<DirectoryTree> directory_tree TSA_GUARDED_BY(mutex);

    mutable CurrentMetrics::Increment remote_layout_directories_count TSA_GUARDED_BY(mutex);
    mutable CurrentMetrics::Increment remote_layout_files_count TSA_GUARDED_BY(mutex);
};

}

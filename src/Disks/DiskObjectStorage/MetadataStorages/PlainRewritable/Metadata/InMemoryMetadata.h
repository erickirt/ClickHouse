#pragma once

#include <Disks/DiskObjectStorage/MetadataStorages/PlainRewritable/Metadata/DirectoryTree.h>

#include <Common/CurrentMetrics.h>

#include <base/defines.h>

namespace DB
{

class InMemoryMetadata
{
public:
    InMemoryMetadata();

    void apply(std::shared_ptr<DirectoryTree> snapshot);
    void apply(std::unordered_map<std::string, DirectoryRemoteInfo> remote_layout);

    std::shared_ptr<DirectoryTree> takeSnapshot() const;

private:
    mutable std::mutex mutex;
    std::shared_ptr<DirectoryTree> directory_tree;

    mutable CurrentMetrics::Increment remote_layout_directories_count;
    mutable CurrentMetrics::Increment remote_layout_files_count;
};

}

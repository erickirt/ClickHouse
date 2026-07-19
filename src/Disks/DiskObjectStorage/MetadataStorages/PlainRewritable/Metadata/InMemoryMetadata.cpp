#include <Disks/DiskObjectStorage/MetadataStorages/PlainRewritable/Metadata/InMemoryMetadata.h>

namespace DB
{

InMemoryMetadata::InMemoryMetadata(CurrentMetrics::Metric metric_directories_name, CurrentMetrics::Metric metric_files_name)
    : directory_tree(std::make_shared<DirectoryTree>())
    , remote_layout_directories_count(metric_directories_name, 0)
    , remote_layout_files_count(metric_files_name, 0)
{
}

void InMemoryMetadata::applySnapshot(std::shared_ptr<DirectoryTree> snapshot)
{
    const auto [directories_delta, files_delta] = snapshot->getRemoteLayoutDeltas();

    std::lock_guard guard(mutex);
    directory_tree = std::move(snapshot);
    remote_layout_directories_count.add(directories_delta);
    remote_layout_files_count.add(files_delta);
}

void InMemoryMetadata::applyLayout(std::unordered_map<std::string, DirectoryRemoteInfo> remote_layout)
{
    auto new_tree = std::make_shared<DirectoryTree>();
    for (auto & [path, info] : remote_layout)
        new_tree->recordDirectoryPath(path, std::move(info));

    const auto [directories_count, files_count] = new_tree->getRemoteLayoutDeltas();

    std::lock_guard guard(mutex);
    directory_tree = std::move(new_tree);
    remote_layout_directories_count.changeTo(directories_count);
    remote_layout_files_count.changeTo(files_count);
}

std::shared_ptr<DirectoryTree> InMemoryMetadata::takeSnapshot() const
{
    std::lock_guard guard(mutex);
    return std::make_shared<DirectoryTree>(directory_tree->getRoot());
}

std::shared_ptr<const DirectoryTree> InMemoryMetadata::takeReadSnapshot() const
{
    std::lock_guard guard(mutex);
    return directory_tree;
}

}

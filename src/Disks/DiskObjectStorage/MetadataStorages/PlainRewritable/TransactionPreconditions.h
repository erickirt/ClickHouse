#pragma once

#include <Disks/DiskObjectStorage/MetadataStorages/PlainRewritable/InMemoryDirectoryTree.h>
#include <Disks/DiskObjectStorage/MetadataStorages/NormalizedPath.h>

#include <base/defines.h>

#include <unordered_map>
#include <unordered_set>

namespace DB
{

class TransactionPreconditions
{
public:
    void checkDirectoryPresent(std::filesystem::path directory, std::string remote_path);
    void checkDirectoryMissing(std::filesystem::path directory);

    void runChecks(const std::shared_ptr<InMemoryDirectoryTree> & fs_tree);

private:
    std::mutex mutex;
    std::unordered_map<std::filesystem::path, std::string> expected_directory_remote_paths TSA_GUARDED_BY(mutex);
    std::unordered_set<std::filesystem::path> expected_missing_directories TSA_GUARDED_BY(mutex);
};

}

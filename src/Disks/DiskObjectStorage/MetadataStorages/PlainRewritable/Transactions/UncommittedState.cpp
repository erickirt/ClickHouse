#include <Disks/DiskObjectStorage/MetadataStorages/PlainRewritable/Transactions/UncommittedState.h>
#include <Disks/DiskObjectStorage/MetadataStorages/NormalizedPath.h>

#include <Common/getRandomASCIIString.h>

#include <ranges>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

namespace DB
{

class UncommittedState::PathResolver
{
public:
    void recordMove(const NormalizedPath & from, const NormalizedPath & to)
    {
        owned_prefixes.push_back(resolveToSnapshotPath(from));
        moves.emplace_back(from, to);
    }

    void recordRemove(const NormalizedPath & directory)
    {
        owned_prefixes.push_back(resolveToSnapshotPath(directory));
    }

    void recordCreate(const NormalizedPath & directory)
    {
        created_directories.insert(resolveToSnapshotPath(directory));
    }

    NormalizedPath resolveToSnapshotPath(const NormalizedPath & path) const
    {
        auto resolved = path.string();

        for (const auto & [from, to] : moves | std::views::reverse)
        {
            if (resolved == to)
                resolved = from;
            else if (resolved.starts_with(to + '/'))
                resolved = from + resolved.substr(to.size());
        }

        return NormalizedPath{resolved};
    }

    bool isOwnedByTransaction(const NormalizedPath & path) const
    {
        const auto & path_string = path.native();

        for (const auto & prefix : owned_prefixes)
            if (path_string == prefix || path_string.starts_with(prefix + '/'))
                return true;

        return false;
    }

    bool isCreatedByTransaction(const NormalizedPath & path) const
    {
        return created_directories.contains(path);
    }

private:
    std::vector<std::pair<std::string, std::string>> moves;
    std::vector<std::string> owned_prefixes;
    std::unordered_set<std::string> created_directories;
};

UncommittedState::UncommittedState(std::shared_ptr<FsSnapshot> tx_snapshot_)
    : tx_snapshot(std::move(tx_snapshot_))
    , preconditions(std::make_shared<Preconditions>())
    , path_resolver(std::make_shared<PathResolver>())
{
}

void UncommittedState::createDirectory(const std::string & path)
{
    if (tx_snapshot->getDirectoryRemoteInfo(path))
    {
        useDirectory(path);
        return;
    }

    const auto snapshot_path = path_resolver->resolveToSnapshotPath(normalizePath(path));
    if (!path_resolver->isOwnedByTransaction(snapshot_path))
        preconditions->checkDirectoryMissing(snapshot_path);

    path_resolver->recordCreate(normalizePath(path));
    tx_snapshot->recordDirectoryPath(path, DirectoryRemoteInfo{ .remote_path = getRandomASCIIString(32), .etag = "", .files = {}});
}

void UncommittedState::removeDirectory(const std::string & path)
{
    if (!tx_snapshot->existsDirectory(path).first)
        return;

    useDirectory(path);

    path_resolver->recordRemove(normalizePath(path));
    tx_snapshot->removeDirectory(path);
}

void UncommittedState::moveDirectory(const std::string & path_from, const std::string & path_to)
{
    if (!tx_snapshot->existsDirectory(path_from).first)
        return;

    if (tx_snapshot->existsDirectory(path_to).first || tx_snapshot->existsFile(path_to))
        return;

    useDirectory(path_from);

    path_resolver->recordMove(normalizePath(path_from), normalizePath(path_to));
    tx_snapshot->moveDirectory(path_from, path_to);
}

std::pair<bool, std::optional<DirectoryRemoteInfo>> UncommittedState::lookupDirectory(const std::string & path) const
{
    useDirectory(path);
    return tx_snapshot->existsDirectory(path);
}

void UncommittedState::useDirectory(const std::string & path) const
{
    const auto info = tx_snapshot->getDirectoryRemoteInfo(path);
    if (!info)
        return;

    const auto snapshot_path = path_resolver->resolveToSnapshotPath(normalizePath(path));
    if (!path_resolver->isCreatedByTransaction(snapshot_path))
        preconditions->checkDirectoryPresent(snapshot_path, info->remote_path);
}

std::shared_ptr<Preconditions> UncommittedState::getTxPreconditions() const
{
    return preconditions;
}

}

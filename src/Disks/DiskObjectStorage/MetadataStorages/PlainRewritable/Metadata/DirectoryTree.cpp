#include <Disks/DiskObjectStorage/MetadataStorages/PlainRewritable/Metadata/DirectoryTree.h>

#include <Common/Exception.h>

#include <base/defines.h>

#include <filesystem>
#include <functional>
#include <memory>
#include <optional>
#include <ranges>
#include <vector>

namespace DB
{

namespace ErrorCodes
{
    extern const int LOGICAL_ERROR;
}

namespace
{

using FsNodePtr = std::shared_ptr<FsNode>;
using FsNodeConstPtr = std::shared_ptr<const FsNode>;

bool isVirtual(const FsNodePtr & node)
{
    return !node->info.has_value();
}

template <class Ptr>
Ptr walk(Ptr node, const NormalizedPath & path)
{
    for (const auto & step : path)
    {
        const auto it = node->subdirectories.find(step);
        if (it == node->subdirectories.end())
            return nullptr;

        node = it->second;
    }

    return node;
}

void traverseNode(const std::string & path, const FsNodePtr & start, const std::function<void(const std::string &, const FsNodePtr &)> & observe)
{
    std::vector<std::pair<std::filesystem::path, FsNodePtr>> unvisited;
    unvisited.emplace_back(path, start);

    while (!unvisited.empty())
    {
        auto [node_path, node] = std::move(unvisited.back());
        unvisited.pop_back();

        observe(node_path, node);

        unvisited.reserve(unvisited.size() + node->subdirectories.size());
        for (const auto & [subdir, subnode] : node->subdirectories)
            unvisited.emplace_back(node_path / subdir, subnode);
    }
}

void checkNoFileConflictsOnPath(const FsNodePtr & root, const NormalizedPath & path)
{
    auto node = root;
    std::filesystem::path parent_path;

    for (const auto & step : path)
    {
        if (!isVirtual(node) && node->info->files.contains(step))
            throw Exception(ErrorCodes::LOGICAL_ERROR, "There is a file '{}' under the path '{}', can't create a directory with the same name", step.string(), parent_path.string());

        if (const auto it = node->subdirectories.find(step); it == node->subdirectories.end())
            return;
        else
            node = it->second;

        parent_path /= step;
    }
}

std::pair<FsNodePtr, FsNodePtr> clonePath(const FsNodePtr & start, const NormalizedPath & path)
{
    FsNodePtr cloned_start = std::make_shared<FsNode>(*start);
    FsNodePtr node = cloned_start;

    for (const auto & step : path)
    {
        FsNodePtr cloned_child;
        if (auto it = node->subdirectories.find(step); it != node->subdirectories.end())
            cloned_child = std::make_shared<FsNode>(*it->second);
        else
            cloned_child = std::make_shared<FsNode>();

        node->subdirectories[step] = cloned_child;
        node = std::move(cloned_child);
    }

    return {std::move(cloned_start), std::move(node)};
}

void trimPath(FsNodePtr node, const NormalizedPath & path)
{
    std::vector<std::pair<FsNodePtr, std::string>> spine;
    for (const auto & step : path)
    {
        spine.emplace_back(node, step);
        node = node->subdirectories.at(step);
    }

    for (const auto & [parent, name] : spine | std::views::reverse)
    {
        const FsNodePtr & child = parent->subdirectories.at(name);
        if (!isVirtual(child) || !child->subdirectories.empty())
            break;

        parent->subdirectories.erase(name);
    }
}

FsNodePtr updateInfo(const FsNodePtr & root, const NormalizedPath & path, const DirectoryRemoteInfo & new_info)
{
    const auto [cloned_root, cloned_leaf] = clonePath(root, path);
    cloned_leaf->info = new_info;
    return cloned_root;
}

FsNodePtr moveTree(const FsNodePtr & root, const NormalizedPath & from, const NormalizedPath & to)
{
    chassert(!from.empty());
    chassert(!to.empty());
    chassert(!walk(root, to));

    const FsNodePtr detached = walk(root, from);
    chassert(detached);

    const auto [without_subtree, cloned_from_parent] = clonePath(root, from.parent_path());
    cloned_from_parent->subdirectories.erase(from.filename());
    trimPath(without_subtree, from.parent_path());

    const auto [cloned_root, cloned_to_parent] = clonePath(without_subtree, to.parent_path());
    cloned_to_parent->subdirectories[to.filename()] = detached;

    return cloned_root;

}

FsNodePtr unlinkTree(const FsNodePtr & root, const NormalizedPath & path)
{
    chassert(!path.empty());
    chassert(walk(root, path));

    const auto [cloned_root, cloned_parent] = clonePath(root, path.parent_path());
    cloned_parent->subdirectories.erase(path.filename());
    trimPath(cloned_root, path.parent_path());

    return cloned_root;
}

}

DirectoryTree::DirectoryTree()
    : root(std::make_shared<FsNode>())
{
}

DirectoryTree::DirectoryTree(std::shared_ptr<FsNode> root_)
    : root(std::move(root_))
{
}

void DirectoryTree::recordDirectoryPath(const std::string & path, DirectoryRemoteInfo info)
{
    std::lock_guard guard(mutex);
    const auto normalized_path = normalizePath(path);

    if (const auto node = walk(root, normalized_path); node && !isVirtual(node))
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Directory '{}' was already recorded", normalized_path.string());

    checkNoFileConflictsOnPath(root, normalized_path);

    root = updateInfo(root, normalized_path, info);
    remote_layout_directories_delta += 1;
    remote_layout_files_delta += info.files.size();
}

void DirectoryTree::moveDirectory(const std::string & from, const std::string & to)
{
    std::lock_guard guard(mutex);
    const auto normalized_from = normalizePath(from);
    const auto normalized_to = normalizePath(to);

    const auto node_from = walk(root, normalized_from);
    if (!node_from)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Directory '{}' does not exist", normalized_from.string());

    if (normalized_from.empty())
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Directory '{}' is root", normalized_from.string());

    if (normalized_to.string().starts_with(normalized_from.string() + '/'))
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Directory '{}' can't be moved to '{}' inside itself", normalized_from.string(), normalized_to.string());

    if (walk(root, normalized_to))
        throw Exception(ErrorCodes::LOGICAL_ERROR, "There is a subdirectory '{}' under the path '{}', can't move", normalized_to.filename().string(), normalized_to.parent_path().string());

    checkNoFileConflictsOnPath(root, normalized_to);

    root = moveTree(root, normalized_from, normalized_to);
}

void DirectoryTree::removeDirectory(const std::string & path)
{
    std::lock_guard guard(mutex);
    const auto normalized_path = normalizePath(path);
    const auto node = walk(root, normalized_path);

    if (!node)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Directory '{}' does not exist", normalized_path.string());

    if (normalized_path.empty())
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Directory '{}' is root", normalized_path.string());

    root = unlinkTree(root, normalized_path);

    traverseNode("", node, [&](const std::string &, const FsNodePtr & subtree_node) TSA_REQUIRES(mutex)
    {
        if (isVirtual(subtree_node))
            return;

        remote_layout_files_delta -= subtree_node->info->files.size();
        remote_layout_directories_delta -= 1;
    });
}

void DirectoryTree::recordFile(const std::string & path, FileRemoteInfo info)
{
    std::lock_guard guard(mutex);
    const auto normalized_path = normalizePath(path);
    const auto node = walk(root, normalized_path.parent_path());

    if (!node)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Directory '{}' does not exist", normalized_path.string());

    if (isVirtual(node))
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Creation of a file under the virtual directory is not possible");

    if (node->subdirectories.contains(normalized_path.filename()))
        throw Exception(ErrorCodes::LOGICAL_ERROR, "There is a subdirectory '{}' under the path '{}'. Can't create file", normalized_path.filename().string(), normalized_path.parent_path().string());

    if (node->info->files.contains(normalized_path.filename()))
        throw Exception(ErrorCodes::LOGICAL_ERROR, "File '{}' already exists", normalized_path.string());

    auto new_directory_info = node->info.value();
    new_directory_info.files.emplace(normalized_path.filename(), std::move(info));
    root = updateInfo(root, normalized_path.parent_path(), new_directory_info);
    remote_layout_files_delta += 1;
}

void DirectoryTree::removeFile(const std::string & path)
{
    std::lock_guard guard(mutex);
    const auto normalized_path = normalizePath(path);
    const auto node = walk(root, normalized_path.parent_path());

    if (!node)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Directory '{}' does not exist", normalized_path.string());

    if (isVirtual(node))
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Removal of a file under the virtual directory is not possible");

    if (!node->info->files.contains(normalized_path.filename()))
        throw Exception(ErrorCodes::LOGICAL_ERROR, "File '{}' does not exist", normalized_path.string());

    auto new_directory_info = node->info.value();
    new_directory_info.files.erase(normalized_path.filename());
    root = updateInfo(root, normalized_path.parent_path(), new_directory_info);
    remote_layout_files_delta -= 1;
}

std::vector<std::string> DirectoryTree::listDirectory(const std::string & path) const
{
    std::lock_guard guard(mutex);
    const auto node = walk(root, normalizePath(path));

    if (!node)
        return {};

    std::vector<std::string> result;
    result.append_range(node->subdirectories | std::views::keys);

    if (!isVirtual(node))
        result.append_range(node->info->files | std::views::keys);

    return result;
}

std::pair<bool, std::optional<DirectoryRemoteInfo>> DirectoryTree::existsDirectory(const std::string & path) const
{
    std::lock_guard guard(mutex);
    const auto node = walk(root, normalizePath(path));

    if (!node)
        return {false, std::nullopt};

    return {true, node->info};
}

std::unordered_map<std::string, std::optional<DirectoryRemoteInfo>> DirectoryTree::getSubtreeRemoteInfo(const std::string & path) const
{
    std::lock_guard guard(mutex);
    const auto normalized_path = normalizePath(path);
    const auto start_node = walk(root, normalized_path);

    if (!start_node)
        return {};

    std::unordered_map<std::string, std::optional<DirectoryRemoteInfo>> subtree_info;
    traverseNode("", start_node, [&subtree_info](const std::string & node_path, const FsNodePtr & node)
    {
        subtree_info[node_path] = node->info;
    });

    return subtree_info;
}

std::optional<DirectoryRemoteInfo> DirectoryTree::getDirectoryRemoteInfo(const std::string & path) const
{
    std::lock_guard guard(mutex);
    const auto node = walk(root, normalizePath(path));

    if (!node)
        return std::nullopt;

    return node->info;
}

std::optional<FileRemoteInfo> DirectoryTree::getFileRemoteInfo(const std::string & path) const
{
    const auto normalized_path = normalizePath(path);
    const auto directory_remote_info = getDirectoryRemoteInfo(normalized_path.parent_path());

    if (!directory_remote_info)
        return std::nullopt;

    if (!directory_remote_info->files.contains(normalized_path.filename()))
        return std::nullopt;

    return directory_remote_info->files.at(normalized_path.filename());
}

bool DirectoryTree::existsFile(const std::string & path) const
{
    std::lock_guard guard(mutex);
    const auto normalized_path = normalizePath(path);
    const auto node = walk(root, normalized_path.parent_path());

    if (!node || isVirtual(node))
        return false;

    return node->info->files.contains(normalized_path.filename());
}

std::shared_ptr<FsNode> DirectoryTree::getRoot() const
{
    std::lock_guard guard(mutex);
    return root;
}

std::pair<int64_t, int64_t> DirectoryTree::getRemoteLayoutDeltas() const
{
    std::lock_guard guard(mutex);
    return {remote_layout_directories_delta, remote_layout_files_delta};
}

}

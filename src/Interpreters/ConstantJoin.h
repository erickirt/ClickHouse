#pragma once

#include <atomic>
#include <list>
#include <memory>
#include <optional>

#include <Core/Block.h>
#include <Core/Field.h>
#include <Interpreters/IJoin.h>
#include <Interpreters/RowRefs.h>
#include <Interpreters/TemporaryDataOnDisk.h>
#include <Common/Logger.h>

namespace DB
{

class TableJoin;

/** Implements joins with constant predicates, including `CROSS JOIN` and comma joins.
  * It stores right-side blocks without hash keys and emits cartesian or default rows according to the join kind,
  * strictness, and constant predicate value.
  * Right-side blocks may be compressed or spilled to a temporary block stream when join limits are exceeded.
  */
class ConstantJoin final : public IJoin
{
public:
    ConstantJoin(std::shared_ptr<TableJoin> table_join_, SharedHeader right_sample_block_, bool any_take_last_row_ = false);

    std::string getName() const override { return "ConstantJoin"; }
    const TableJoin & getTableJoin() const override { return *table_join; }

    bool isCloneSupported() const override
    {
        return getTotals().empty() && total_rows_to_join == 0;
    }

    std::shared_ptr<IJoin> clone(
        const std::shared_ptr<TableJoin> & table_join_,
        SharedHeader,
        SharedHeader right_sample_block_) const override
    {
        return std::make_shared<ConstantJoin>(table_join_, right_sample_block_, any_take_last_row);
    }

    bool addBlockToJoin(const Block & source_block, bool check_limits) override;
    bool addBlockToJoin(const Block & source_block, size_t num_rows, bool check_limits) override;

    void checkTypesOfKeys(const Block &) const override {}

    JoinResultPtr joinBlock(Block block) override;

    size_t getTotalRowCount() const override { return in_memory_rows; }
    size_t getTotalByteCount() const override;

    bool alwaysReturnsEmptySet() const override;

    IBlocksStreamPtr getNonJoinedBlocks(const Block & left_sample_block, const Block & result_sample_block, UInt64 max_block_size) const override;

private:
    friend class ConstantJoinResult;
    friend class ConstantJoinNotJoinedRightFiller;

    /// A right-side block prepared for probing. `rows` can be non-zero while `columns_info` is empty
    /// when the query needs only the right-side row count.
    struct StoredBlock
    {
        ColumnsInfo columns_info;
        size_t rows = 0;

        StoredBlock(ColumnsInfo columns_info_, size_t rows_)
            : columns_info(std::move(columns_info_))
            , rows(rows_)
        {
        }

        size_t allocatedBytes() const;
    };

    using StoredBlocks = std::list<StoredBlock>;

    enum class PredicateKind
    {
        /// A predicate that always matches: explicit `CROSS`/comma join or a join without `ON`/`USING`.
        True,
        /// The old analyzer can encode constant-false `JOIN ON` as no keys with an `ON` expression.
        /// The new analyzer normally uses `CompareConstantKeys` with dummy constant keys for this case.
        False,
        /// A constant `JOIN ON` represented as one equality between left and right dummy constant keys.
        CompareConstantKeys,
    };

    std::shared_ptr<TableJoin> table_join;

    /// Header of the right columns appended to every output row (excludes the dummy constant key).
    Block sample_block_with_columns_to_add;
    /// Empty block with the structure the stored right blocks are normalized to.
    Block saved_block_sample;

    /// Right-side data kept in memory, possibly compressed.
    StoredBlocks right_blocks;

    /// Spilling of right blocks once the join size limits are approached; `tmp_stream` exists after the first spill.
    TemporaryDataOnDiskScopePtr tmp_data;
    std::optional<TemporaryBlockStreamHolder> tmp_stream;

    /// All right rows, including spilled ones.
    size_t total_rows_to_join = 0;
    /// Rows residing in `right_blocks` only.
    size_t in_memory_rows = 0;
    /// Incrementally maintained sum of `StoredBlock::allocatedBytes` over `right_blocks`.
    size_t allocated_size = 0;
    /// At least one stored block is compressed; readers then decompress every stored block.
    bool have_compressed = false;
    /// The single right row joined by the selected-right-row modes (first or last, see `useLastRightRow`).
    std::optional<ColumnsInfo> selected_right_columns_info;

    PredicateKind predicate_kind = PredicateKind::True;
    /// The dummy constant key names; set only for `PredicateKind::CompareConstantKeys`.
    String left_constant_key_name;
    String right_constant_key_name;
    /// Value of the right dummy key, captured from the first right block.
    std::optional<Field> right_constant_key_value;
    /// Lazily cached result of `CompareConstantKeys`: -1 unknown, 0 no match, 1 match.
    std::atomic<Int32> constant_predicate_match = -1;
    /// Whether any probe rows have matched; gates the non-joined right rows and the first-left-row cut in `joinBlock`.
    std::atomic_bool has_seen_matching_rows = false;
    /// The `join_any_take_last_row` setting (see `useLastRightRow`).
    const bool any_take_last_row;

    /// Per-result-block limits: `max_joined_block_size_rows` / `max_joined_block_size_bytes`.
    size_t max_joined_block_rows = 0;
    size_t max_joined_block_bytes = 0;

    /// Set under memory pressure; from then on stored blocks are shrunk to fit (see `shrinkStoredBlocksToFit`).
    bool shrink_blocks = false;
    /// Query memory usage at the first `addBlockToJoin`; the baseline for measuring the join's own consumption.
    Int64 memory_usage_before_adding_blocks = 0;

    LoggerPtr log;

    bool constantPredicateMatches(const Block & left_block);
    void shrinkStoredBlocksToFit(size_t & total_bytes_in_join);
    void doDebugAsserts() const;
};

}

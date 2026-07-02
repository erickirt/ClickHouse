#include <Interpreters/ConstantJoin.h>

#include <algorithm>
#include <limits>
#include <vector>

#include <base/arithmeticOverflow.h>

#include <Columns/ColumnReplicated.h>
#include <Common/Exception.h>
#include <Common/formatReadable.h>
#include <Common/logger_useful.h>
#include <Core/Joins.h>
#include <Interpreters/JoinUtils.h>
#include <Interpreters/TableJoin.h>

namespace DB
{

namespace ErrorCodes
{
    extern const int LOGICAL_ERROR;
    extern const int SET_SIZE_LIMIT_EXCEEDED;
}

namespace
{

/// Intentionally mirrors `HashJoin`: `join_any_take_last_row` affects the modes that join one selected right row
/// (see `selected_right_columns_info`), and never the `RIGHT` kinds, which join all right rows.
bool useLastRightRow(JoinKind kind, JoinStrictness strictness, bool any_take_last_row)
{
    return any_take_last_row && strictness == JoinStrictness::Any && !isRight(kind);
}

}

size_t ConstantJoin::StoredBlock::allocatedBytes() const
{
    /// Stored columns always hold exactly `rows` rows; blocks that carry only a row count have no columns.
    chassert(columns_info.columns.empty() || columns_info.columns.front()->size() == rows);

    if (rows == 0)
        return 0;

    size_t res = 0;
    for (const auto & column : columns_info.columns)
        res += column->allocatedBytes();

    return res;
}

ConstantJoin::ConstantJoin(std::shared_ptr<TableJoin> table_join_, SharedHeader right_sample_block_, bool any_take_last_row_)
    : table_join(std::move(table_join_))
    , tmp_data(table_join->getTempDataOnDisk())
    , any_take_last_row(any_take_last_row_)
    , max_joined_block_rows(table_join->maxJoinedBlockRows())
    , max_joined_block_bytes(table_join->maxJoinedBlockBytes())
    , log(getLogger("ConstantJoin"))
{
    bool is_cross_or_comma = isCrossOrComma(table_join->kind());
    bool is_join_with_constant = table_join->isJoinWithConstant();
    bool is_no_key_join = table_join->getClauses().empty();
    if (!is_cross_or_comma && !is_join_with_constant && !is_no_key_join)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "ConstantJoin expects CROSS, comma or JOIN ON constant, got {}", table_join->kind());

    bool is_no_clause_join = is_no_key_join && !table_join->hasOn() && !table_join->hasUsing();

    if (is_cross_or_comma || is_no_clause_join)
        predicate_kind = PredicateKind::True;
    else if (is_join_with_constant && table_join->oneDisjunct())
        predicate_kind = PredicateKind::CompareConstantKeys;
    else
        predicate_kind = PredicateKind::False;

    Block right_sample_block = *right_sample_block_;
    JoinCommon::createMissedColumns(right_sample_block);

    if (predicate_kind == PredicateKind::CompareConstantKeys)
    {
        const auto & clause = table_join->getOnlyClause();
        if (clause.key_names_left.size() != 1 || clause.key_names_right.size() != 1)
            throw Exception(ErrorCodes::LOGICAL_ERROR, "ConstantJoin expects one constant key on each join side");

        left_constant_key_name = clause.key_names_left.front();
        right_constant_key_name = clause.key_names_right.front();

        Block right_constant_key;
        JoinCommon::splitAdditionalColumns(clause.key_names_right, right_sample_block, right_constant_key, sample_block_with_columns_to_add);
    }
    else
        sample_block_with_columns_to_add = materializeBlock(right_sample_block);

    JoinCommon::createMissedColumns(sample_block_with_columns_to_add);
    saved_block_sample = sample_block_with_columns_to_add.cloneEmpty();

    LOG_TEST(log, "Right header: {}", right_sample_block.dumpStructure());
}

bool ConstantJoin::addBlockToJoin(const Block & source_block, bool check_limits)
{
    return addBlockToJoin(source_block, source_block.rows(), check_limits);
}

bool ConstantJoin::addBlockToJoin(const Block & source_block, size_t num_rows, bool check_limits)
{
    if (num_rows && predicate_kind == PredicateKind::CompareConstantKeys && !right_constant_key_value)
        right_constant_key_value = source_block.getByName(right_constant_key_name).column->operator[](0);

    auto materialized = JoinCommon::materializeColumnsFromRightBlock(source_block, saved_block_sample);

    size_t rows = materialized.rows();
    if (rows == 0 && num_rows != 0 && !materialized.columns())
        rows = num_rows;

    if (!memory_usage_before_adding_blocks)
        memory_usage_before_adding_blocks = JoinCommon::getCurrentQueryMemoryUsage();

    total_rows_to_join += rows;

    Block block_to_save = JoinCommon::filterColumnsPresentInSampleBlock(materialized, saved_block_sample);
    if (shrink_blocks)
        block_to_save = block_to_save.shrinkToFit();

    if (rows)
    {
        /// `SEMI` and old `ANY` (`RightAny`) use the first right row. New `ANY` may use the last one,
        /// depending on the setting.
        bool take_last_right_row = useLastRightRow(table_join->kind(), table_join->strictness(), any_take_last_row);
        if (take_last_right_row || !selected_right_columns_info)
            selected_right_columns_info.emplace(block_to_save.cloneWithCutColumns(take_last_right_row ? rows - 1 : 0, 1).getColumns());
    }

    size_t max_bytes_in_join = table_join->sizeLimits().max_bytes;
    size_t max_rows_in_join = table_join->sizeLimits().max_rows;

    /// Empty blocks can still represent rows when no right-side columns are needed by the query.
    /// Keep them in memory as row-count metadata because Native format cannot persist that row count without columns.
    bool can_spill_block = block_to_save.columns() != 0;
    if (can_spill_block && tmp_data
        && (tmp_stream || (max_bytes_in_join && getTotalByteCount() + block_to_save.allocatedBytes() >= max_bytes_in_join)
            || (max_rows_in_join && getTotalRowCount() + block_to_save.rows() >= max_rows_in_join)))
    {
        if (!tmp_stream)
            tmp_stream.emplace(std::make_shared<const Block>(sample_block_with_columns_to_add), tmp_data);

        tmp_stream.value()->write(block_to_save);
        return true;
    }

    assertBlocksHaveEqualStructureAllowReplicated(saved_block_sample, block_to_save, "joined block");

    size_t min_bytes_to_compress = table_join->crossJoinMinBytesToCompress();
    size_t min_rows_to_compress = table_join->crossJoinMinRowsToCompress();

    if ((min_bytes_to_compress && getTotalByteCount() >= min_bytes_to_compress)
        || (min_rows_to_compress && getTotalRowCount() >= min_rows_to_compress))
    {
        block_to_save = block_to_save.compress();
        have_compressed = true;
    }

    doDebugAsserts();
    right_blocks.emplace_back(ColumnsInfo(block_to_save.getColumns()), rows);
    auto & stored_block = right_blocks.back();
    allocated_size += stored_block.allocatedBytes();
    in_memory_rows += rows;
    doDebugAsserts();

    size_t total_rows = getTotalRowCount();
    size_t total_bytes = getTotalByteCount();
    shrinkStoredBlocksToFit(total_bytes);

    if (!check_limits)
        return true;

    return table_join->sizeLimits().check(total_rows, total_bytes, "JOIN", ErrorCodes::SET_SIZE_LIMIT_EXCEEDED);
}

void ConstantJoin::doDebugAsserts() const
{
#ifdef DEBUG_OR_SANITIZER_BUILD
    size_t debug_allocated_size = 0;
    for (const auto & stored_block : right_blocks)
        debug_allocated_size += stored_block.allocatedBytes();

    if (allocated_size != debug_allocated_size)
        throw Exception(
            ErrorCodes::LOGICAL_ERROR,
            "allocated_size != debug_allocated_size ({} != {})",
            allocated_size,
            debug_allocated_size);
#endif
}

size_t ConstantJoin::getTotalByteCount() const
{
    doDebugAsserts();
    return allocated_size;
}

void ConstantJoin::shrinkStoredBlocksToFit(size_t & total_bytes_in_join)
{
    if (shrink_blocks)
        return;

    Int64 current_memory_usage = JoinCommon::getCurrentQueryMemoryUsage();
    Int64 query_memory_usage_delta = current_memory_usage - memory_usage_before_adding_blocks;
    Int64 max_total_bytes_for_query = memory_usage_before_adding_blocks ? table_join->getMaxMemoryUsage() : 0;

    auto max_total_bytes_in_join = table_join->sizeLimits().max_bytes;

    shrink_blocks = (max_total_bytes_in_join && total_bytes_in_join > max_total_bytes_in_join / 2)
        || (max_total_bytes_for_query && query_memory_usage_delta > max_total_bytes_for_query / 2);
    if (!shrink_blocks)
        return;

    LOG_DEBUG(
        log,
        "Shrinking stored blocks, memory consumption is {} {} calculated by join, {} {} by memory tracker",
        ReadableSize(total_bytes_in_join),
        max_total_bytes_in_join ? fmt::format("/ {}", ReadableSize(max_total_bytes_in_join)) : "",
        ReadableSize(query_memory_usage_delta),
        max_total_bytes_for_query ? fmt::format("/ {}", ReadableSize(max_total_bytes_for_query)) : "");

    for (auto & stored_block : right_blocks)
    {
        doDebugAsserts();

        size_t old_size = stored_block.allocatedBytes();

        try
        {
            for (auto & column : stored_block.columns_info.columns)
                column = column->cloneResized(column->size());

            stored_block.columns_info.rebuildReplicatedColumns();
        }
        catch (...)
        {
            stored_block.columns_info.rebuildReplicatedColumns();
            size_t partial_new_size = stored_block.allocatedBytes();
            if (old_size >= partial_new_size)
                allocated_size -= old_size - partial_new_size;
            else
                allocated_size += partial_new_size - old_size;
            throw;
        }

        size_t new_size = stored_block.allocatedBytes();

        if (old_size >= new_size)
        {
            if (allocated_size < old_size - new_size)
                throw Exception(
                    ErrorCodes::LOGICAL_ERROR,
                    "Blocks allocated size value is broken: blocks_allocated_size = {}, old_size = {}, new_size = {}",
                    allocated_size,
                    old_size,
                    new_size);

            allocated_size -= old_size - new_size;
        }
        else
            allocated_size += new_size - old_size;

        doDebugAsserts();
    }

    auto new_total_bytes_in_join = getTotalByteCount();
    Int64 new_current_memory_usage = JoinCommon::getCurrentQueryMemoryUsage();

    LOG_DEBUG(
        log,
        "Shrunk stored blocks {} freed ({} by memory tracker), new memory consumption is {} ({} by memory tracker)",
        ReadableSize(total_bytes_in_join - new_total_bytes_in_join),
        ReadableSize(current_memory_usage - new_current_memory_usage),
        ReadableSize(new_total_bytes_in_join),
        ReadableSize(new_current_memory_usage));

    total_bytes_in_join = new_total_bytes_in_join;
}

bool ConstantJoin::constantPredicateMatches(const Block & left_block)
{
    switch (predicate_kind)
    {
        case PredicateKind::True:
            return true;
        case PredicateKind::False:
            return false;
        case PredicateKind::CompareConstantKeys:
            break;
    }

    if (!right_constant_key_value || left_block.rows() == 0)
        return false;

    Int32 cached_match = constant_predicate_match.load(std::memory_order_acquire);
    if (cached_match != -1)
        return cached_match == 1;

    /// The left key is a dummy constant column produced by the join ActionsDAG, so after the first non-empty
    /// left block its value is fixed for the whole join.
    bool matches = left_block.getByName(left_constant_key_name).column->operator[](0) == *right_constant_key_value;
    constant_predicate_match.store(matches ? 1 : 0, std::memory_order_release);
    return matches;
}

namespace
{

enum class MatchingRowsOutput
{
    None,
    All,
    /// The selected right row is the first or last stored right row, chosen at build time (see `useLastRightRow`).
    AllLeftRowsWithSelectedRightRow,
    FirstLeftRowWithSelectedRightRow,
    FirstLeftRowWithAllRightRows,
};

/// Modes where only the first matching probe row joins the right side; `joinBlock` cuts the probe block accordingly.
bool usesOnlyFirstLeftRow(MatchingRowsOutput output)
{
    return output == MatchingRowsOutput::FirstLeftRowWithSelectedRightRow
        || output == MatchingRowsOutput::FirstLeftRowWithAllRightRows;
}

bool usesSelectedRightRow(MatchingRowsOutput output)
{
    return output == MatchingRowsOutput::AllLeftRowsWithSelectedRightRow
        || output == MatchingRowsOutput::FirstLeftRowWithSelectedRightRow;
}

MatchingRowsOutput makeMatchingRowsOutput(JoinKind kind, JoinStrictness strictness, bool has_match)
{
    if (!has_match)
        return MatchingRowsOutput::None;

    if (isCrossOrComma(kind))
        return MatchingRowsOutput::All;

    if (strictness == JoinStrictness::Any)
    {
        if (isRight(kind))
            return MatchingRowsOutput::FirstLeftRowWithAllRightRows;
        if (isInner(kind))
            return MatchingRowsOutput::FirstLeftRowWithSelectedRightRow;
        return MatchingRowsOutput::AllLeftRowsWithSelectedRightRow;
    }

    if (strictness == JoinStrictness::RightAny)
    {
        /// Intentionally mirrors `HashJoin`: old `ANY` assumes distinct right keys and emits one right row for
        /// each matching left row. `RIGHT` and `FULL` unmatched right rows are handled by
        /// `output_non_matching_right_rows`.
        return MatchingRowsOutput::AllLeftRowsWithSelectedRightRow;
    }

    if (strictness == JoinStrictness::All)
        return MatchingRowsOutput::All;

    if (strictness == JoinStrictness::Semi)
        return kind == JoinKind::Right ? MatchingRowsOutput::FirstLeftRowWithAllRightRows
                                       : MatchingRowsOutput::AllLeftRowsWithSelectedRightRow;

    return MatchingRowsOutput::None;
}

struct ConstantJoinOutputFlags
{
    MatchingRowsOutput output_matching_rows = MatchingRowsOutput::None;
    bool output_non_matching_left_rows = false;
    bool output_non_matching_right_rows = false;
};

/// Classifies which rows one evaluation of the join emits. It is a pure function of its arguments;
/// `alwaysReturnsEmptySet` relies on that to enumerate hypothetical scenarios.
///
/// `has_match` — whether the left rows under classification match the right side, i.e. the constant predicate is
/// true and the right side is not empty. It describes one evaluation, not the whole join: the non-joined stream
/// (`getNonJoinedBlocks`) always passes false because it processes no left rows.
///
/// `has_seen_matching_rows` — whether any probe rows have matched so far (the accumulated member of the same
/// name). It only gates `output_non_matching_right_rows`: `RIGHT`/`FULL` kinds emit the stored right rows as
/// non-matching only when no left row ever claimed them.
///
/// `has_match && !has_seen_matching_rows` cannot occur: a matching probe block sets `has_seen_matching_rows`
/// before its result is constructed.
ConstantJoinOutputFlags makeConstantJoinOutputFlags(JoinKind kind, JoinStrictness strictness, bool has_match, bool has_seen_matching_rows)
{
    ConstantJoinOutputFlags flags;
    flags.output_matching_rows = makeMatchingRowsOutput(kind, strictness, has_match);

    /// Explicit cartesian joins never emit non-matching rows, regardless of strictness.
    if (isCrossOrComma(kind))
        return flags;

    const bool is_right_semi = kind == JoinKind::Right && strictness == JoinStrictness::Semi;
    const bool is_right_anti = kind == JoinKind::Right && strictness == JoinStrictness::Anti;

    flags.output_non_matching_left_rows =
        (strictness == JoinStrictness::Anti && !has_match && !is_right_anti)
        || (strictness != JoinStrictness::Semi && strictness != JoinStrictness::Anti && !has_match && isLeftOrFull(kind));
    flags.output_non_matching_right_rows = isRightOrFull(kind)
        && !is_right_semi
        && !has_seen_matching_rows;

    return flags;
}

ColumnsInfo decompressColumns(const ColumnsInfo & columns_info)
{
    Columns new_columns;
    new_columns.reserve(columns_info.columns.size());
    for (const auto & column : columns_info.columns)
        new_columns.emplace_back(column->decompress());

    return ColumnsInfo(std::move(new_columns));
}

void insertRangeFromColumnsInfo(MutableColumns & dst_columns, size_t dst_offset, const ColumnsInfo & columns_info, size_t start, size_t rows)
{
    for (size_t col_num = 0; col_num < columns_info.columns.size(); ++col_num)
    {
        if (const auto * replicated_column = columns_info.replicated_columns[col_num])
        {
            for (size_t row = start; row != start + rows; ++row)
                dst_columns[dst_offset + col_num]->insertFrom(
                    *replicated_column->getNestedColumn(),
                    replicated_column->getIndexes().getIndexAt(row));
        }
        else
            dst_columns[dst_offset + col_num]->insertRangeFrom(*columns_info.columns[col_num], start, rows);
    }
}

}

bool ConstantJoin::alwaysReturnsEmptySet() const
{
    const auto kind = table_join->kind();
    const auto strictness = table_join->strictness();

    auto can_output = [&](bool has_match, bool has_seen_matching_rows_)
    {
        const auto output_flags = makeConstantJoinOutputFlags(kind, strictness, has_match, has_seen_matching_rows_);
        return output_flags.output_matching_rows != MatchingRowsOutput::None
            || output_flags.output_non_matching_left_rows
            || (total_rows_to_join != 0 && output_flags.output_non_matching_right_rows);
    };

    auto predicate_always_returns_empty_set = [&](bool predicate_matches)
    {
        if (!predicate_matches || total_rows_to_join == 0)
            return !can_output(/* has_match */ false, /* has_seen_matching_rows_ */ false);

        /// Consider all left-side cardinalities. For example, `RIGHT SEMI JOIN ON 1` can emit
        /// right rows only after at least one left row was seen, while `RIGHT ANTI JOIN ON 1`
        /// can emit right rows only when no left rows were seen.
        return !can_output(/* has_match */ true, /* has_seen_matching_rows_ */ true)
            && !can_output(/* has_match */ false, /* has_seen_matching_rows_ */ false)
            && !can_output(/* has_match */ false, /* has_seen_matching_rows_ */ true);
    };

    switch (predicate_kind)
    {
        case PredicateKind::True:
            return predicate_always_returns_empty_set(true);
        case PredicateKind::False:
            return predicate_always_returns_empty_set(false);
        case PredicateKind::CompareConstantKeys:
        {
            const auto cached_match = constant_predicate_match.load(std::memory_order_acquire);
            if (cached_match == -1)
                return false;

            return predicate_always_returns_empty_set(cached_match == 1);
        }
    }

    UNREACHABLE();
}

class ConstantJoinResult final : public IJoinResult
{
public:
    ConstantJoinResult(const ConstantJoin & join_, Block block_, bool has_match_)
        : join(join_)
        , block(std::move(block_))
        , output_flags(makeConstantJoinOutputFlags(
            join.table_join->kind(),
            join.table_join->strictness(),
            has_match_,
            join.has_seen_matching_rows.load()))
    {
        src_left_columns.reserve(block.columns());
        for (size_t i = 0; i != block.columns(); ++i)
        {
            const auto & left_column = block.getByPosition(i);
            if (join.predicate_kind == ConstantJoin::PredicateKind::CompareConstantKeys
                && left_column.name == join.left_constant_key_name)
                continue;

            result_sample.insert(left_column);
            src_left_columns.push_back(left_column.column.get());
        }

        for (const auto & right_column : join.sample_block_with_columns_to_add)
            result_sample.insert(right_column);
    }

    JoinResultBlock next() override;

private:
    const ConstantJoin & join;
    Block block;
    ConstantJoinOutputFlags output_flags;
    /// The result header and raw pointers to the left data columns; invariant across `next` calls.
    Block result_sample;
    ColumnRawPtrs src_left_columns;
    size_t left_row = 0;
    std::optional<ConstantJoin::StoredBlocks::const_iterator> right_block_it;
    std::optional<TemporaryBlockStreamReaderHolder> reader;
};

IJoinResult::JoinResultBlock ConstantJoinResult::next()
{
    const size_t num_existing_columns = src_left_columns.size();
    const size_t num_columns_to_add = join.sample_block_with_columns_to_add.columns();
    const size_t rows_total = block.rows();

    MutableColumns dst_columns = result_sample.cloneEmptyColumns();

    /// Reserve the exact output size of the current mode (`enough_data` may still cut it short).
    size_t to_reserve = 0;
    switch (output_flags.output_matching_rows)
    {
        case MatchingRowsOutput::All:
            if (common::mulOverflow(rows_total, join.total_rows_to_join, to_reserve))
                to_reserve = join.max_joined_block_rows;
            break;
        case MatchingRowsOutput::AllLeftRowsWithSelectedRightRow:
            to_reserve = rows_total;
            break;
        case MatchingRowsOutput::FirstLeftRowWithSelectedRightRow:
            to_reserve = 1;
            break;
        case MatchingRowsOutput::FirstLeftRowWithAllRightRows:
            to_reserve = join.total_rows_to_join;
            break;
        case MatchingRowsOutput::None:
            to_reserve = output_flags.output_non_matching_left_rows ? rows_total : 0;
            break;
    }
    /// Without a row cap do not pre-reserve: the estimates of `All` and `FirstLeftRowWithAllRightRows` are not
    /// bounded by the probe block, while `max_joined_block_bytes` may still chunk the output into much smaller
    /// blocks, so reserving the full estimate could allocate far more than one output block ever holds.
    /// `HashJoin` skips reservation for `max_joined_block_rows = 0` the same way.
    if (join.max_joined_block_rows)
        to_reserve = std::min(join.max_joined_block_rows, to_reserve);
    else
        to_reserve = 0;

    for (auto & dst : dst_columns)
        dst->reserve(to_reserve);
    size_t rows_added = 0;
    size_t bytes_added = 0;

    auto enough_data = [&]()
    {
        return (join.max_joined_block_rows && rows_added > join.max_joined_block_rows)
            || (join.max_joined_block_bytes && bytes_added > join.max_joined_block_bytes);
    };

    auto update_bytes = [&]()
    {
        if (!join.max_joined_block_bytes)
            return;

        bytes_added = 0;
        for (const auto & dst : dst_columns)
            bytes_added += dst->byteSize();
    };

    auto insert_left_rows = [&](size_t rows)
    {
        for (size_t col_num = 0; col_num < num_existing_columns; ++col_num)
            dst_columns[col_num]->insertManyFrom(*src_left_columns[col_num], left_row, rows);
    };

    auto insert_right_defaults = [&](size_t rows)
    {
        for (size_t col_num = 0; col_num < num_columns_to_add; ++col_num)
        {
            const auto & right_column = join.sample_block_with_columns_to_add.getByPosition(col_num);
            JoinCommon::addDefaultValues(*dst_columns[num_existing_columns + col_num], right_column.type, rows);
        }
    };

    auto process_right_block = [&](const ColumnsInfo & columns_info, size_t rows_right)
    {
        rows_added += rows_right;
        insert_left_rows(rows_right);
        insertRangeFromColumnsInfo(dst_columns, num_existing_columns, columns_info, 0, rows_right);
        update_bytes();
    };

    auto process_default_right = [&]()
    {
        ++rows_added;
        insert_left_rows(1);
        insert_right_defaults(1);
        update_bytes();
    };

    if (output_flags.output_matching_rows == MatchingRowsOutput::None && !output_flags.output_non_matching_left_rows)
        left_row = rows_total;

    for (; left_row < rows_total; ++left_row)
    {
        if (enough_data())
            break;

        if (output_flags.output_non_matching_left_rows)
        {
            process_default_right();
            continue;
        }

        if (usesSelectedRightRow(output_flags.output_matching_rows))
        {
            if (join.selected_right_columns_info)
                process_right_block(*join.selected_right_columns_info, 1);
            continue;
        }

        chassert(
            output_flags.output_matching_rows == MatchingRowsOutput::All
            || output_flags.output_matching_rows == MatchingRowsOutput::FirstLeftRowWithAllRightRows);
        if (!right_block_it.has_value())
            right_block_it = join.right_blocks.begin();

        for (; *right_block_it != join.right_blocks.end(); ++*right_block_it)
        {
            if (enough_data())
                break;

            const auto & stored_block = **right_block_it;
            if (!join.have_compressed)
                process_right_block(stored_block.columns_info, stored_block.rows);
            else
                process_right_block(decompressColumns(stored_block.columns_info), stored_block.rows);
        }

        if (*right_block_it != join.right_blocks.end())
            break;

        if (join.tmp_stream)
        {
            if (!reader)
                reader = join.tmp_stream->getReadStream();

            while (reader)
            {
                if (enough_data())
                    break;

                auto block_right = reader.value()->read();
                if (block_right.empty())
                {
                    reader.reset();
                    break;
                }

                process_right_block(ColumnsInfo(block_right.getColumns()), block_right.rows());
            }
        }

        if (reader)
            break;

        right_block_it = std::nullopt;
    }

    bool is_last = left_row >= rows_total;
    auto res = result_sample.cloneWithColumns(std::move(dst_columns));
    return {res, nullptr, is_last};
}

class ConstantJoinNotJoinedRightFiller final : public NotJoinedBlocks::RightColumnsFiller
{
public:
    ConstantJoinNotJoinedRightFiller(const ConstantJoin & join_, UInt64 max_block_size_)
        : join(join_)
        , max_block_size(max_block_size_ ? max_block_size_ : std::numeric_limits<UInt64>::max())
    {
    }

    Block getEmptyBlock() override { return join.sample_block_with_columns_to_add.cloneEmpty(); }

    size_t fillColumns(MutableColumns & columns_right) override
    {
        size_t rows_added = 0;

        auto insert_rows = [&](const ColumnsInfo & columns_info, size_t start, size_t rows)
        {
            insertRangeFromColumnsInfo(columns_right, 0, columns_info, start, rows);
            rows_added += rows;
        };

        if (!right_block_it)
            right_block_it = join.right_blocks.begin();

        for (; *right_block_it != join.right_blocks.end() && rows_added < max_block_size; ++*right_block_it)
        {
            const auto & stored_block = **right_block_it;
            size_t rows_available = stored_block.rows - right_block_offset;
            size_t rows_to_take = std::min<size_t>(rows_available, max_block_size - rows_added);
            if (rows_to_take == 0)
            {
                right_block_offset = 0;
                continue;
            }

            if (!join.have_compressed)
                insert_rows(stored_block.columns_info, right_block_offset, rows_to_take);
            else
            {
                /// A block wider than `max_block_size` is emitted in several chunks: decompress it only once.
                if (!current_decompressed_columns_info)
                    current_decompressed_columns_info.emplace(decompressColumns(stored_block.columns_info));

                insert_rows(*current_decompressed_columns_info, right_block_offset, rows_to_take);
            }

            right_block_offset += rows_to_take;
            if (right_block_offset != stored_block.rows)
                return rows_added;

            right_block_offset = 0;
            current_decompressed_columns_info.reset();
        }

        if (*right_block_it != join.right_blocks.end())
            return rows_added;

        if (!join.tmp_stream)
            return rows_added;

        if (!reader)
            reader = join.tmp_stream->getReadStream();

        while (reader && rows_added < max_block_size)
        {
            if (!current_spilled_columns_info)
            {
                auto block_right = reader.value()->read();
                if (block_right.empty())
                {
                    reader.reset();
                    break;
                }

                current_spilled_rows = block_right.rows();
                current_spilled_columns_info.emplace(block_right.getColumns());
            }

            size_t rows_available = current_spilled_rows - right_block_offset;
            size_t rows_to_take = std::min<size_t>(rows_available, max_block_size - rows_added);
            if (rows_to_take == 0)
            {
                current_spilled_columns_info.reset();
                current_spilled_rows = 0;
                right_block_offset = 0;
                continue;
            }

            insert_rows(*current_spilled_columns_info, right_block_offset, rows_to_take);

            right_block_offset += rows_to_take;
            if (right_block_offset != current_spilled_rows)
                return rows_added;

            current_spilled_columns_info.reset();
            current_spilled_rows = 0;
            right_block_offset = 0;
        }

        return rows_added;
    }

private:
    const ConstantJoin & join;
    UInt64 max_block_size;
    std::optional<ConstantJoin::StoredBlocks::const_iterator> right_block_it;
    size_t right_block_offset = 0;
    std::optional<ColumnsInfo> current_decompressed_columns_info;
    std::optional<TemporaryBlockStreamReaderHolder> reader;
    std::optional<ColumnsInfo> current_spilled_columns_info;
    size_t current_spilled_rows = 0;
};

JoinResultPtr ConstantJoin::joinBlock(Block block)
{
    /// A constant predicate cannot match rows of an empty right side; `alwaysReturnsEmptySet` applies the same rule.
    bool has_match = constantPredicateMatches(block) && total_rows_to_join != 0;
    if (has_match && block.rows())
    {
        if (usesOnlyFirstLeftRow(makeMatchingRowsOutput(table_join->kind(), table_join->strictness(), /* has_match */ true)))
        {
            /// Probe streams race here: exactly one matching block keeps its first row, all others become empty.
            bool expected = false;
            if (has_seen_matching_rows.compare_exchange_strong(expected, true))
                block = block.cloneWithCutColumns(0, 1);
            else
                block = block.cloneEmpty();
        }
        else
            has_seen_matching_rows = true;
    }

    return std::make_unique<ConstantJoinResult>(*this, std::move(block), has_match);
}

IBlocksStreamPtr ConstantJoin::getNonJoinedBlocks(const Block &, const Block & result_sample_block, UInt64 max_block_size) const
{
    if (total_rows_to_join == 0)
        return {};

    auto output_flags = makeConstantJoinOutputFlags(
        table_join->kind(),
        table_join->strictness(),
        /* has_match */ false,
        has_seen_matching_rows.load());

    if (!output_flags.output_non_matching_right_rows)
        return {};

    auto filler = std::make_unique<ConstantJoinNotJoinedRightFiller>(*this, max_block_size);
    size_t left_columns_count = result_sample_block.columns() - sample_block_with_columns_to_add.columns();
    return std::make_shared<NotJoinedBlocks>(std::move(filler), result_sample_block, left_columns_count, *table_join);
}

}

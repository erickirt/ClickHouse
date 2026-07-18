-- Regression test for https://github.com/ClickHouse/ClickHouse/issues/110898
-- A QBit value truncated to `precision` bit planes is reconstructed to the centre of its coarse cell (the most
-- significant dropped bit is set), not to the cell's lower edge (dropped bits zero-filled). Zero-filling made
-- 1-bit BFloat16 reconstruction collapse to +-0.0: the reconstructed vector was the zero vector, so the distance
-- was the same for every row and carried no ranking information. With the centre fill, 1-bit reconstruction is a
-- proper sign quantization, consistent with the QBit(Int8) Lloyd-Max path (LloydMax::transposedDequantLUT).

DROP TABLE IF EXISTS qbit_recon;
CREATE TABLE qbit_recon (id UInt32, bf QBit(BFloat16, 8)) ENGINE = MergeTree ORDER BY id;

-- 5 vectors with distinct sign patterns: element i of row n is +-0.5 depending on bit i of n
INSERT INTO qbit_recon
SELECT number, arrayMap(i -> toBFloat16(0.5 * if(bitTest(number, i), 1, -1)), range(8))
FROM numbers(5);

SELECT '-- 1-bit cosine distance ranks by sign (used to be constant 1 for every row)';
SET optimize_qbit_distance_function_reads = 0;
SELECT id,
       round(cosineDistance(CAST(bf, 'Array(Float32)'), [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]), 4) AS true_cos,
       round(cosineDistanceTransposed(bf, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 1), 4) AS bf16_1bit
FROM qbit_recon ORDER BY id;

SET optimize_qbit_distance_function_reads = 1;
SELECT id,
       round(cosineDistance(CAST(bf, 'Array(Float32)'), [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]), 4) AS true_cos,
       round(cosineDistanceTransposed(bf, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 1), 4) AS bf16_1bit
FROM qbit_recon ORDER BY id;

SELECT '-- 1-bit L2 distance distinguishes sign patterns too';
SELECT id,
       round(L2DistanceTransposed(bf, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 1), 4) AS bf16_1bit_l2
FROM qbit_recon ORDER BY id;

DROP TABLE qbit_recon;

-- Read out the reconstructed first coordinate through a dot product with a one-hot reference vector.
-- BFloat16 1.0 is 0x3F80: at precision 1 only the sign survives and the centre fill gives +-2.0 (not +-0.0);
-- at precision 8 the fill restores the dropped exponent LSB, reconstructing 1.0 exactly; at precision 9 the
-- most significant dropped mantissa bit is set, giving 1.5; precision 16 keeps all bits.
SELECT '-- BFloat16 reconstruction of +-1.0 at precisions 1, 8, 9, 16';
WITH [1.0, -1.0]::QBit(BFloat16, 2) AS v, [1.0, 0.0]::Array(BFloat16) AS first, [0.0, 1.0]::Array(BFloat16) AS second
SELECT dotProductTransposed(v, first, 1), dotProductTransposed(v, second, 1),
       dotProductTransposed(v, first, 8), dotProductTransposed(v, second, 8),
       dotProductTransposed(v, first, 9), dotProductTransposed(v, second, 9),
       dotProductTransposed(v, first, 16), dotProductTransposed(v, second, 16);

SELECT '-- Float32 and Float64 reconstruction of +-1.0 at precision 1';
WITH [1.0, -1.0]::QBit(Float32, 2) AS v, [1.0, 0.0]::Array(Float32) AS first, [0.0, 1.0]::Array(Float32) AS second
SELECT dotProductTransposed(v, first, 1), dotProductTransposed(v, second, 1);
WITH [1.0, -1.0]::QBit(Float64, 2) AS v, [1.0, 0.0]::Array(Float64) AS first, [0.0, 1.0]::Array(Float64) AS second
SELECT dotProductTransposed(v, first, 1), dotProductTransposed(v, second, 1);

SELECT '-- Int8 reconstruction of 100 and -100 at precision 1 (cell centre +-64, not 0/-128)';
WITH [100, -100]::QBit(Int8, 2) AS v, [1, 0]::Array(Int8) AS first, [0, 1]::Array(Int8) AS second
SELECT dotProductTransposed(v, first, 1), dotProductTransposed(v, second, 1);

-- A stored 0 must stay 0 at reduced precision, otherwise the generic centre fill turns an all-zero float cell into a
-- positive constant, injecting a fake direction into zero or padded dimensions (so reduced-precision cosine distance
-- would report identical zero vectors as maximally dissimilar). At precision >= 2 the retained exponent bits mark the
-- all-zero cell as genuinely near-zero, so a float type keeps it at exact 0; the reviewer's repro then yields 0, not 1.
SELECT '-- Zero cell: reduced-precision cosine of identical zero BFloat16 vectors is 0, not 1';
SELECT cosineDistanceTransposed([0.0]::QBit(BFloat16, 1), [0.0]::Array(BFloat16), 8) AS bf16_zero_cos_p8;

-- The first coordinate is exactly 0: at precision >= 2 every float type reconstructs it to 0; at precision 1 (pure sign
-- quantization) it shares the positive sign and reconstructs to the positive centre, as sign quantization requires.
SELECT '-- Zero coordinate reconstructs to 0 at precision >= 2 (to +centre at precision 1) for BFloat16, Float32, Float64';
WITH [0.0, 1.0]::QBit(BFloat16, 2) AS v, [1.0, 0.0]::Array(BFloat16) AS first
SELECT dotProductTransposed(v, first, 1) AS bf16_p1, dotProductTransposed(v, first, 2) AS bf16_p2, dotProductTransposed(v, first, 8) AS bf16_p8;
WITH [0.0, 1.0]::QBit(Float32, 2) AS v, [1.0, 0.0]::Array(Float32) AS first
SELECT dotProductTransposed(v, first, 1) AS f32_p1, dotProductTransposed(v, first, 2) AS f32_p2, dotProductTransposed(v, first, 16) AS f32_p16;
WITH [0.0, 1.0]::QBit(Float64, 2) AS v, [1.0, 0.0]::Array(Float64) AS first
SELECT dotProductTransposed(v, first, 1) AS f64_p1, dotProductTransposed(v, first, 2) AS f64_p2, dotProductTransposed(v, first, 32) AS f64_p32;

-- Int8 has no exponent, so an all-zero kept prefix is a uniform range of small non-negative codes, not a near-zero
-- magnitude: the raw Int8 path keeps the unconditional centre for its all-zero cell (0 -> +centre), unchanged.
SELECT '-- Int8 keeps the unconditional centre for its all-zero cell';
WITH [0, 100]::QBit(Int8, 2) AS v, [1, 0]::Array(Int8) AS first
SELECT dotProductTransposed(v, first, 2) AS int8_zero_p2;

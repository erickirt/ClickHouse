-- Correctness of groupBitOr/groupBitAnd/groupBitXor batch paths for all integer
-- types: plain, -If, Nullable and Nullable + -If, verified against an arrayFold
-- with the scalar bit functions; plus identity values for empty selections.

SELECT
    'UInt8',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'UInt8')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'UInt8'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'UInt8')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'UInt8')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'UInt8'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'UInt8')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'UInt8')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'UInt8'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'UInt8')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'UInt8')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'UInt8'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'UInt8'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toUInt8(bitAnd(cityHash64(number, 1), 255)) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'UInt8 identity', groupBitOrIf(v, c0) = CAST(0, 'UInt8'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'UInt8')), groupBitXorIf(v, c0) = CAST(0, 'UInt8') FROM (SELECT toUInt8(bitAnd(cityHash64(number, 1), 255)) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'UInt8 empty', groupBitOr(v) = CAST(0, 'UInt8'), groupBitAnd(v) = bitNot(CAST(0, 'UInt8')), groupBitXor(v) = CAST(0, 'UInt8') FROM (SELECT toUInt8(bitAnd(cityHash64(number, 1), 255)) AS v FROM numbers(100) WHERE number > 100);
SELECT 'UInt8 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toUInt8(bitAnd(cityHash64(number, 1), 255))) AS vn FROM numbers(100));

SELECT
    'UInt16',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'UInt16')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'UInt16'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'UInt16')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'UInt16')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'UInt16'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'UInt16')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'UInt16')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'UInt16'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'UInt16')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'UInt16')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'UInt16'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'UInt16'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toUInt16(bitAnd(cityHash64(number, 1), 65535)) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'UInt16 identity', groupBitOrIf(v, c0) = CAST(0, 'UInt16'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'UInt16')), groupBitXorIf(v, c0) = CAST(0, 'UInt16') FROM (SELECT toUInt16(bitAnd(cityHash64(number, 1), 65535)) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'UInt16 empty', groupBitOr(v) = CAST(0, 'UInt16'), groupBitAnd(v) = bitNot(CAST(0, 'UInt16')), groupBitXor(v) = CAST(0, 'UInt16') FROM (SELECT toUInt16(bitAnd(cityHash64(number, 1), 65535)) AS v FROM numbers(100) WHERE number > 100);
SELECT 'UInt16 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toUInt16(bitAnd(cityHash64(number, 1), 65535))) AS vn FROM numbers(100));

SELECT
    'UInt32',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'UInt32')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'UInt32'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'UInt32')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'UInt32')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'UInt32'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'UInt32')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'UInt32')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'UInt32'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'UInt32')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'UInt32')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'UInt32'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'UInt32'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toUInt32(bitAnd(cityHash64(number, 1), 4294967295)) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'UInt32 identity', groupBitOrIf(v, c0) = CAST(0, 'UInt32'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'UInt32')), groupBitXorIf(v, c0) = CAST(0, 'UInt32') FROM (SELECT toUInt32(bitAnd(cityHash64(number, 1), 4294967295)) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'UInt32 empty', groupBitOr(v) = CAST(0, 'UInt32'), groupBitAnd(v) = bitNot(CAST(0, 'UInt32')), groupBitXor(v) = CAST(0, 'UInt32') FROM (SELECT toUInt32(bitAnd(cityHash64(number, 1), 4294967295)) AS v FROM numbers(100) WHERE number > 100);
SELECT 'UInt32 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toUInt32(bitAnd(cityHash64(number, 1), 4294967295))) AS vn FROM numbers(100));

SELECT
    'UInt64',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'UInt64')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'UInt64'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'UInt64')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'UInt64')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'UInt64'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'UInt64')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'UInt64')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'UInt64'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'UInt64')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'UInt64')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'UInt64'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'UInt64'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT cityHash64(number, 1) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'UInt64 identity', groupBitOrIf(v, c0) = CAST(0, 'UInt64'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'UInt64')), groupBitXorIf(v, c0) = CAST(0, 'UInt64') FROM (SELECT cityHash64(number, 1) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'UInt64 empty', groupBitOr(v) = CAST(0, 'UInt64'), groupBitAnd(v) = bitNot(CAST(0, 'UInt64')), groupBitXor(v) = CAST(0, 'UInt64') FROM (SELECT cityHash64(number, 1) AS v FROM numbers(100) WHERE number > 100);
SELECT 'UInt64 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, cityHash64(number, 1)) AS vn FROM numbers(100));

SELECT
    'UInt128',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'UInt128')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'UInt128'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'UInt128')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'UInt128')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'UInt128'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'UInt128')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'UInt128')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'UInt128'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'UInt128')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'UInt128')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'UInt128'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'UInt128'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt128'), 64), CAST(cityHash64(number, 2), 'UInt128')) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'UInt128 identity', groupBitOrIf(v, c0) = CAST(0, 'UInt128'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'UInt128')), groupBitXorIf(v, c0) = CAST(0, 'UInt128') FROM (SELECT bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt128'), 64), CAST(cityHash64(number, 2), 'UInt128')) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'UInt128 empty', groupBitOr(v) = CAST(0, 'UInt128'), groupBitAnd(v) = bitNot(CAST(0, 'UInt128')), groupBitXor(v) = CAST(0, 'UInt128') FROM (SELECT bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt128'), 64), CAST(cityHash64(number, 2), 'UInt128')) AS v FROM numbers(100) WHERE number > 100);
SELECT 'UInt128 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt128'), 64), CAST(cityHash64(number, 2), 'UInt128'))) AS vn FROM numbers(100));

SELECT
    'UInt256',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'UInt256')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'UInt256'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'UInt256')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'UInt256')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'UInt256'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'UInt256')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'UInt256')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'UInt256'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'UInt256')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'UInt256')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'UInt256'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'UInt256'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT bitOr(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt256'), 192), bitShiftLeft(CAST(cityHash64(number, 2), 'UInt256'), 128)), bitOr(bitShiftLeft(CAST(cityHash64(number, 3), 'UInt256'), 64), CAST(cityHash64(number, 4), 'UInt256'))) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'UInt256 identity', groupBitOrIf(v, c0) = CAST(0, 'UInt256'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'UInt256')), groupBitXorIf(v, c0) = CAST(0, 'UInt256') FROM (SELECT bitOr(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt256'), 192), bitShiftLeft(CAST(cityHash64(number, 2), 'UInt256'), 128)), bitOr(bitShiftLeft(CAST(cityHash64(number, 3), 'UInt256'), 64), CAST(cityHash64(number, 4), 'UInt256'))) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'UInt256 empty', groupBitOr(v) = CAST(0, 'UInt256'), groupBitAnd(v) = bitNot(CAST(0, 'UInt256')), groupBitXor(v) = CAST(0, 'UInt256') FROM (SELECT bitOr(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt256'), 192), bitShiftLeft(CAST(cityHash64(number, 2), 'UInt256'), 128)), bitOr(bitShiftLeft(CAST(cityHash64(number, 3), 'UInt256'), 64), CAST(cityHash64(number, 4), 'UInt256'))) AS v FROM numbers(100) WHERE number > 100);
SELECT 'UInt256 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, bitOr(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt256'), 192), bitShiftLeft(CAST(cityHash64(number, 2), 'UInt256'), 128)), bitOr(bitShiftLeft(CAST(cityHash64(number, 3), 'UInt256'), 64), CAST(cityHash64(number, 4), 'UInt256')))) AS vn FROM numbers(100));

SELECT
    'Int8',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'Int8')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'Int8'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'Int8')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'Int8')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'Int8'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'Int8')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'Int8')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'Int8'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'Int8')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'Int8')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'Int8'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'Int8'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toInt8(toUInt8(bitAnd(cityHash64(number, 1), 255))) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'Int8 identity', groupBitOrIf(v, c0) = CAST(0, 'Int8'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'Int8')), groupBitXorIf(v, c0) = CAST(0, 'Int8') FROM (SELECT toInt8(toUInt8(bitAnd(cityHash64(number, 1), 255))) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'Int8 empty', groupBitOr(v) = CAST(0, 'Int8'), groupBitAnd(v) = bitNot(CAST(0, 'Int8')), groupBitXor(v) = CAST(0, 'Int8') FROM (SELECT toInt8(toUInt8(bitAnd(cityHash64(number, 1), 255))) AS v FROM numbers(100) WHERE number > 100);
SELECT 'Int8 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toInt8(toUInt8(bitAnd(cityHash64(number, 1), 255)))) AS vn FROM numbers(100));

SELECT
    'Int16',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'Int16')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'Int16'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'Int16')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'Int16')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'Int16'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'Int16')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'Int16')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'Int16'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'Int16')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'Int16')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'Int16'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'Int16'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toInt16(toUInt16(bitAnd(cityHash64(number, 1), 65535))) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'Int16 identity', groupBitOrIf(v, c0) = CAST(0, 'Int16'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'Int16')), groupBitXorIf(v, c0) = CAST(0, 'Int16') FROM (SELECT toInt16(toUInt16(bitAnd(cityHash64(number, 1), 65535))) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'Int16 empty', groupBitOr(v) = CAST(0, 'Int16'), groupBitAnd(v) = bitNot(CAST(0, 'Int16')), groupBitXor(v) = CAST(0, 'Int16') FROM (SELECT toInt16(toUInt16(bitAnd(cityHash64(number, 1), 65535))) AS v FROM numbers(100) WHERE number > 100);
SELECT 'Int16 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toInt16(toUInt16(bitAnd(cityHash64(number, 1), 65535)))) AS vn FROM numbers(100));

SELECT
    'Int32',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'Int32')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'Int32'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'Int32')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'Int32')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'Int32'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'Int32')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'Int32')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'Int32'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'Int32')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'Int32')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'Int32'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'Int32'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toInt32(toUInt32(bitAnd(cityHash64(number, 1), 4294967295))) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'Int32 identity', groupBitOrIf(v, c0) = CAST(0, 'Int32'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'Int32')), groupBitXorIf(v, c0) = CAST(0, 'Int32') FROM (SELECT toInt32(toUInt32(bitAnd(cityHash64(number, 1), 4294967295))) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'Int32 empty', groupBitOr(v) = CAST(0, 'Int32'), groupBitAnd(v) = bitNot(CAST(0, 'Int32')), groupBitXor(v) = CAST(0, 'Int32') FROM (SELECT toInt32(toUInt32(bitAnd(cityHash64(number, 1), 4294967295))) AS v FROM numbers(100) WHERE number > 100);
SELECT 'Int32 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toInt32(toUInt32(bitAnd(cityHash64(number, 1), 4294967295)))) AS vn FROM numbers(100));

SELECT
    'Int64',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'Int64')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'Int64'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'Int64')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'Int64')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'Int64'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'Int64')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'Int64')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'Int64'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'Int64')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'Int64')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'Int64'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'Int64'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toInt64(cityHash64(number, 1)) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'Int64 identity', groupBitOrIf(v, c0) = CAST(0, 'Int64'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'Int64')), groupBitXorIf(v, c0) = CAST(0, 'Int64') FROM (SELECT toInt64(cityHash64(number, 1)) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'Int64 empty', groupBitOr(v) = CAST(0, 'Int64'), groupBitAnd(v) = bitNot(CAST(0, 'Int64')), groupBitXor(v) = CAST(0, 'Int64') FROM (SELECT toInt64(cityHash64(number, 1)) AS v FROM numbers(100) WHERE number > 100);
SELECT 'Int64 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toInt64(cityHash64(number, 1))) AS vn FROM numbers(100));

SELECT
    'Int128',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'Int128')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'Int128'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'Int128')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'Int128')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'Int128'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'Int128')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'Int128')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'Int128'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'Int128')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'Int128')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'Int128'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'Int128'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toInt128(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt128'), 64), CAST(cityHash64(number, 2), 'UInt128'))) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'Int128 identity', groupBitOrIf(v, c0) = CAST(0, 'Int128'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'Int128')), groupBitXorIf(v, c0) = CAST(0, 'Int128') FROM (SELECT toInt128(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt128'), 64), CAST(cityHash64(number, 2), 'UInt128'))) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'Int128 empty', groupBitOr(v) = CAST(0, 'Int128'), groupBitAnd(v) = bitNot(CAST(0, 'Int128')), groupBitXor(v) = CAST(0, 'Int128') FROM (SELECT toInt128(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt128'), 64), CAST(cityHash64(number, 2), 'UInt128'))) AS v FROM numbers(100) WHERE number > 100);
SELECT 'Int128 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toInt128(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt128'), 64), CAST(cityHash64(number, 2), 'UInt128')))) AS vn FROM numbers(100));

SELECT
    'Int256',
    gbOr = arrayFold((acc, e) -> bitOr(acc, e), arr, CAST(0, 'Int256')),
    gbAnd = arrayFold((acc, e) -> bitAnd(acc, e), arr, bitNot(CAST(0, 'Int256'))),
    gbXor = arrayFold((acc, e) -> bitXor(acc, e), arr, CAST(0, 'Int256')),
    gbOrIf = arrayFold((acc, e) -> bitOr(acc, e), arrIf, CAST(0, 'Int256')),
    gbAndIf = arrayFold((acc, e) -> bitAnd(acc, e), arrIf, bitNot(CAST(0, 'Int256'))),
    gbXorIf = arrayFold((acc, e) -> bitXor(acc, e), arrIf, CAST(0, 'Int256')),
    gbOrNull = arrayFold((acc, e) -> bitOr(acc, e), arrNull, CAST(0, 'Int256')),
    gbAndNull = arrayFold((acc, e) -> bitAnd(acc, e), arrNull, bitNot(CAST(0, 'Int256'))),
    gbXorNull = arrayFold((acc, e) -> bitXor(acc, e), arrNull, CAST(0, 'Int256')),
    gbOrNullIf = arrayFold((acc, e) -> bitOr(acc, e), arrNullIf, CAST(0, 'Int256')),
    gbAndNullIf = arrayFold((acc, e) -> bitAnd(acc, e), arrNullIf, bitNot(CAST(0, 'Int256'))),
    gbXorNullIf = arrayFold((acc, e) -> bitXor(acc, e), arrNullIf, CAST(0, 'Int256'))
FROM
(
    SELECT
        groupBitOr(v) AS gbOr,
        groupBitAnd(v) AS gbAnd,
        groupBitXor(v) AS gbXor,
        groupBitOrIf(v, c) AS gbOrIf,
        groupBitAndIf(v, c) AS gbAndIf,
        groupBitXorIf(v, c) AS gbXorIf,
        groupBitOr(vn) AS gbOrNull,
        groupBitAnd(vn) AS gbAndNull,
        groupBitXor(vn) AS gbXorNull,
        groupBitOrIf(vn, c) AS gbOrNullIf,
        groupBitAndIf(vn, c) AS gbAndNullIf,
        groupBitXorIf(vn, c) AS gbXorNullIf,
        groupArray(v) AS arr,
        groupArrayIf(v, c) AS arrIf,
        groupArray(vn) AS arrNull,
        groupArrayIf(vn, c) AS arrNullIf
    FROM (SELECT toInt256(bitOr(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt256'), 192), bitShiftLeft(CAST(cityHash64(number, 2), 'UInt256'), 128)), bitOr(bitShiftLeft(CAST(cityHash64(number, 3), 'UInt256'), 64), CAST(cityHash64(number, 4), 'UInt256')))) AS v, cityHash64(number, 42) % 2 = 0 AS c, if(cityHash64(number, 7) % 4 = 0, NULL, v) AS vn FROM numbers(70000))
);

SELECT 'Int256 identity', groupBitOrIf(v, c0) = CAST(0, 'Int256'), groupBitAndIf(v, c0) = bitNot(CAST(0, 'Int256')), groupBitXorIf(v, c0) = CAST(0, 'Int256') FROM (SELECT toInt256(bitOr(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt256'), 192), bitShiftLeft(CAST(cityHash64(number, 2), 'UInt256'), 128)), bitOr(bitShiftLeft(CAST(cityHash64(number, 3), 'UInt256'), 64), CAST(cityHash64(number, 4), 'UInt256')))) AS v, number > 100 AS c0 FROM numbers(100));
SELECT 'Int256 empty', groupBitOr(v) = CAST(0, 'Int256'), groupBitAnd(v) = bitNot(CAST(0, 'Int256')), groupBitXor(v) = CAST(0, 'Int256') FROM (SELECT toInt256(bitOr(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt256'), 192), bitShiftLeft(CAST(cityHash64(number, 2), 'UInt256'), 128)), bitOr(bitShiftLeft(CAST(cityHash64(number, 3), 'UInt256'), 64), CAST(cityHash64(number, 4), 'UInt256')))) AS v FROM numbers(100) WHERE number > 100);
SELECT 'Int256 allnull', isNull(groupBitOr(vn)), isNull(groupBitAnd(vn)), isNull(groupBitXor(vn)) FROM (SELECT if(number != 999, NULL, toInt256(bitOr(bitOr(bitShiftLeft(CAST(cityHash64(number, 1), 'UInt256'), 192), bitShiftLeft(CAST(cityHash64(number, 2), 'UInt256'), 128)), bitOr(bitShiftLeft(CAST(cityHash64(number, 3), 'UInt256'), 64), CAST(cityHash64(number, 4), 'UInt256'))))) AS vn FROM numbers(100));

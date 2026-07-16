#!/usr/bin/env bash
# Tags: no-fasttest
#       ^ no Parquet support in fasttest
#
# Regression test: parseWKTFormat (ArrowGeoTypes.cpp) must skip leading
# whitespace before the geometry type keyword, matching the SQL readWKT
# dispatcher and the WKT grammar. Before the fix a WKT-encoded GeoParquet
# value like '  POINT (1 2)' produced BAD_ARGUMENTS (type "  POINT" matched
# nothing). Sibling of issue #110700 (readWKT).

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$TMP_DIR" <<'PYEOF'
import sys, json
import pyarrow as pa
import pyarrow.parquet as pq

out = sys.argv[1]

def write_geoparquet(path, ids, wkts, geometry_types):
    geo_meta = {
        "version": "1.1.0",
        "primary_column": "geom",
        "columns": {"geom": {"encoding": "WKT", "geometry_types": geometry_types}},
    }
    table = pa.table({
        "id":   pa.array(ids, type=pa.int32()),
        "geom": pa.array(wkts, type=pa.utf8()),
    })
    meta = table.schema.metadata or {}
    meta[b"geo"] = json.dumps(geo_meta).encode()
    table = table.replace_schema_metadata(meta)
    pq.write_table(table, path)

# Mixed (Geometry) column with leading whitespace (spaces / tab) before the type.
write_geoparquet(
    out + "/wkt_ws.parquet",
    ids=[1, 2, 3, 4, 5],
    wkts=[
        "  POINT (1 2)",
        "\tLINESTRING (0 0, 1 1)",
        "  POLYGON ((1 0, 10 0, 10 10, 0 10, 1 0))",
        " MULTILINESTRING ((1 1, 2 2), (3 3, 4 4))",
        "  MULTIPOLYGON (((2 0, 10 0, 10 10, 0 10, 2 0)))",
    ],
    geometry_types=[],
)
PYEOF

GEO_SETTINGS="--input_format_parquet_use_native_reader_v3=1 --input_format_parquet_allow_geoparquet_parser=1"

$CLICKHOUSE_LOCAL $GEO_SETTINGS -q \
    "SELECT id, variantType(geom), geom FROM file('$TMP_DIR/wkt_ws.parquet', Parquet) ORDER BY id"

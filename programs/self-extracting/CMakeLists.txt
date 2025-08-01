
if (NOT(
        CMAKE_HOST_SYSTEM_NAME STREQUAL CMAKE_SYSTEM_NAME
        AND CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL CMAKE_SYSTEM_PROCESSOR
    )
)
    set (COMPRESSOR "${PROJECT_BINARY_DIR}/native/utils/self-extracting-executable/pre_compressor")
    set (DECOMPRESSOR "--decompressor=${PROJECT_BINARY_DIR}/utils/self-extracting-executable/decompressor")
else ()
    set (COMPRESSOR "${PROJECT_BINARY_DIR}/utils/self-extracting-executable/compressor")
endif ()

set(self_extracting_deps)

add_custom_target (clickhouse-self-extracting ALL
    ${CMAKE_COMMAND} -E remove clickhouse
    COMMAND ${COMPRESSOR} ${DECOMPRESSOR} clickhouse ../clickhouse
    DEPENDS clickhouse compressor
)
list(APPEND self_extracting_deps clickhouse-self-extracting)

if (BUILD_STRIPPED_BINARY)
    add_custom_target (clickhouse-self-extracting-stripped ALL
        ${CMAKE_COMMAND} -E remove clickhouse-stripped
        COMMAND ${COMPRESSOR} ${DECOMPRESSOR} clickhouse-stripped ../clickhouse-stripped
        DEPENDS clickhouse clickhouse-stripped
    )
    list(APPEND self_extracting_deps clickhouse-self-extracting-stripped)
endif()

if (BUILD_STANDALONE_KEEPER)
    add_custom_target (self-extracting-keeper ALL
        ${CMAKE_COMMAND} -E remove clickhouse-keeper
        COMMAND ${COMPRESSOR} ${DECOMPRESSOR} clickhouse-keeper ../clickhouse-keeper
        DEPENDS compressor clickhouse-keeper
    )
    list(APPEND self_extracting_deps self-extracting-keeper)
endif()

add_custom_target (self-extracting ALL
    DEPENDS ${self_extracting_deps}
)

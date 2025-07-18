#!/usr/bin/env bash

set -e -o pipefail

ROOT_PATH="$1"
IFS=$'\t'

echo "// autogenerated by $0"
echo "const char * library_licenses[] = {"
${ROOT_PATH}/utils/list-licenses/list-licenses.sh | while read row; do
    arr=($row)

    echo "\"${arr[0]}\", \"${arr[1]}\", \"${arr[2]}\", R\"heredoc($(cat "${ROOT_PATH}/${arr[2]}"))heredoc\","
    echo
done
echo "nullptr"
echo "};"

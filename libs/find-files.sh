#!/usr/bin/env bash
##########################################################################
# script name: find-files
# script date: 28 Juli 2016
##########################################################################
# find all files and add them to a queue
##########################################################################
# --- include guard -------------------------------------------------
[ -n "${FIND_FILES_SH+x}" ] && return || readonly FIND_FILES_SH=1
# --- global parameters ---------------------------------------------
#set -e          # kill script if a command fails
#set -o nounset  # unset values give error
#set -o pipefail # prevents errors in a pipeline from being masked
# --- include files -------------------------------------------------
SCRIPT_PATH="$(dirname $( realpath ${BASH_SOURCE[0]} ) )"
LIBS_PATH="${SCRIPT_PATH}"
source "${LIBS_PATH}/b-log/b-log.sh"    # logging
source "${LIBS_PATH}/queue.sh"          # queue via file system
# -------------------------------------------------------------------

function find_files() {
    # @description find all files and add them to a queue
    # - find all the files matching the parameters
    # - add them to a queue that will be cleared first
    # @param $1 path to directory
    # @param $2 filename(wildcards accepted)
    # @param $3 filetypes(extensions)
    # @param $4 queue name
    # @param $5 ignore expression
    local path=${1:-"./"}
    local filename=${2:-}
    set -f # temp disable expansion
    # so that wildcards are accepted for the for loop
    local filetypes=(${3:-})
    set +f
    local queue_name=${4:-}
    local ignore=${5:-}
    DEBUG "path: ${path}"
    DEBUG "filename: ${filename}"
    DEBUG "filetypes: ${filetypes[@]:-}"
    DEBUG "queue name: ${queue_name}"
    DEBUG "ignore: ${ignore}"
    queue_init ${queue_name} true
    for filetype in "${filetypes[@]:-}"; do
        DEBUG "filetype: ${filetype}"
        if [ ! -z "${filetype}" ]; then
            find "${path}" -type f -name "${filename}.${filetype}" -not -path "${ignore}" -print0 | while IFS= read -r -d '' file; do
                 queue_add "${queue_name}" "$file"
                 DEBUG "file $file"
            done
        fi
    done
}

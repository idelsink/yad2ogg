#!/bin/bash
##########################################################################
# script name: mutex
# script date: 28 Juli 2016
##########################################################################
# a simple mutex interface
#
# use and manage a simple mutex implementation
# via a local file system
# - lock 'mutex name' [returns 1(succeeded) or 0(failed)]
# - free 'mutex name'
##########################################################################
# --- include guard -------------------------------------------------
[ -n "${MUTEX_SH+x}" ] && return || readonly MUTEX_SH=1
# --- global parameters ---------------------------------------------
#set -e          # kill script if a command fails
#set -o nounset  # unset values give error
#set -o pipefail # prevents errors in a pipeline from being masked
# --- include files -------------------------------------------------
SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_PATH_LOCAL="${SCRIPT_PATH}"
LIBS_PATH="${SCRIPT_PATH}"
LIBS_PATH_LOCAL="${SCRIPT_PATH}"
source "${LIBS_PATH}/b-log/b-log.sh"    # logging
# -------------------------------------------------------------------

function mutex_lock() {
    # @description locks a mutex
    # if no mutex exists, one will be made
    # @param $1 the mutex name
    # @return returns status: true/1(succeeded) or false/0(failed)
    local mutex_name=${1:-}
    local readonly mutex_name_prefix="mutex_"
    local readonly LOCK_FD=200
    if [ -z "$mutex_name" ]; then
        return 0 # missing mutex name
    fi
    #local prefix=`basename $0`
    #prefix+="_$mutex_name"
    local fd=${2:-$LOCK_FD}
    local mutex_file="${LOCKFILE_DIR}/${mutex_name_prefix}${mutex_name}"
    # create lock file
    mkdir -p "$(dirname "${mutex_file}")" || return 0
    touch "${mutex_file}"
    eval "exec $fd>$mutex_file"

    # acquier the lock
    flock -n $fd \
        && return 0 \
        || return 1
}

function mutex_free() {
    # @description frees a mutex
    # use this when you have the mutex
    # of the to be freed mutex
    # @param $1 the mutex name
    local mutex_name=${1:-}
    local readonly mutex_name_prefix="mutex_"
    if [ -z "$mutex_name" ]; then
        return 0 # missing mutex name
    fi
    local mutex_file="${LOCKFILE_DIR}/${mutex_name_prefix}${mutex_name}"
    if [ -e "$mutex_file" ]; then
        rm $mutex_file
    fi
}

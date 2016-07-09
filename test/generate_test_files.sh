#!/bin/bash
#########################################################################
# Script Name: yad2ogg_gen_test_files
# Script Version: 0.0.1
# Script Date: 30 June 2016
#########################################################################
#
# Generate some test files with ffmpeg
#
# example:
# ./generate_test_files.sh -o music/ -t 20 -f 500
#
#########################################################################
# MIT License
#
# Copyright (c) 2016 Ingmar Delsink
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#########################################################################
# include guard
# yad2ogg_gen_test_files
[ -n "${YAD2OGG_GEN_TEST_FILES_SH+x}" ] && return || readonly YAD2OGG_GEN_TEST_FILES_SH=1

# global parameters
# default disable these settings
#set -e          # kill script if a command fails
#set -o nounset  # unset values give error
#set -o pipefail # prevents errors in a pipeline from being masked

VERSION=0.0.1
APPNAME="yad2ogg_gen_test_files"
USAGE="
Usage: command -hVio
-h help
-V version
-t sample duration
-f sample frequency
-r sample rate
-o destination/output directory
"
function PRINT_USAGE() {
    # @description prints the short usage of the script
	echo "$USAGE"
}

# --- global variables ----------------------------------------------
SAMPLE_DURATION=10      # seconds
SAMPLE_FREQUENCY=1000   # hz
SAMPLE_RATE=48000
SAMPLE_OUTPUT_FOLDER="./"
COMMAND=""              # command to execute

# --- options processing --------------------------------------------
if [ $# -eq 0 ] ; then  # nothing past to the script
    PRINT_USAGE
    exit 1;
fi
# get options
while getopts "hVt:f:r:o:" optname
do
    case "$optname" in
        "h")
            PRINT_USAGE
            exit 0;
            ;;
        "V")
            echo "${APPNAME} v${VERSION}"
            exit 0;
            ;;
        "t")
            SAMPLE_DURATION=$OPTARG
            ;;
        "f")
            SAMPLE_FREQUENCY=$OPTARG
            ;;
        "r")
            SAMPLE_RATE=$OPTARG
            ;;
        "o")
            SAMPLE_OUTPUT_FOLDER=$OPTARG
            ;;
        *)
            echo "unknown error while processing options"
            exit 1;
        ;;
    esac
done
shift "$((OPTIND-1))" # shift out all the already processed options

function generate_sample_command() {
    # @description returns a command to run to generate a sample
    # @param $1 the filetype
    # @param $2 extra flags
    # @param $3 filename prefix
    local filetype=${1:-}
    local flags=${2:-}
    local sample_name_prefix="test_file"
    local filename_prefix=${3:-"${sample_name_prefix}"}
    local filename=""
    local base_command="ffmpeg -f lavfi -i \"sine=frequency=${SAMPLE_FREQUENCY}:sample_rate=${SAMPLE_RATE}:duration=${SAMPLE_DURATION}\""
    local command=""
    if [ -z "${filetype}" ]; then
        echo "missing filetype"
        exit 1
    fi
    # {base} {optional flags} {output file}
    filename="${filename_prefix}_${filetype}_T${SAMPLE_DURATION}_F${SAMPLE_FREQUENCY}_R${SAMPLE_RATE}.${filetype}"
    command="${base_command} ${flags} ${SAMPLE_OUTPUT_FOLDER}${filename}"
    echo "${command}"
}


# check output folder
if [ ! -d "${SAMPLE_OUTPUT_FOLDER}" ]; then
    mkdir -p "${SAMPLE_OUTPUT_FOLDER}" || true
fi

#############################
# generate the files
#############################
# lossless
# wav
COMMAND=$(generate_sample_command "wav" "-y")
eval "${COMMAND}" || true

# flac
COMMAND=$(generate_sample_command "flac" "-y")
eval "${COMMAND}" || true

# alac (in m4a container)
COMMAND=$(generate_sample_command "m4a" "-acodec alac -y" "alac_container")
eval "${COMMAND}" || true

# lossy
# MP3
COMMAND=$(generate_sample_command "mp3" "-y")
eval "${COMMAND}" || true

# ogg
COMMAND=$(generate_sample_command "ogg" "-y")
eval "${COMMAND}" || true

# m4a
COMMAND=$(generate_sample_command "m4a" "-strict -2 -y")
eval "${COMMAND}" || true

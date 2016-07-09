#!/bin/bash
#########################################################################
# Script Name: test.sh
# Script Version: 0.0.1
# Script Date: 06 Juli 2016
#########################################################################
#
# A simple yad20gg test script
#
#########################################################################
# global parameters
set -e          # kill script if a command fails
set -o nounset  # unset values give error
set -o pipefail # prevents errors in a pipeline from being masked

SCRIPT_PATH=${0%/*}

INPUT_DIR="${SCRIPT_PATH}/input"
OUTPUT_DIR="${SCRIPT_PATH}/output"

# make input and output folder
if [ ! -w "${INPUT_DIR}" ]; then   # check output directory for write access
    mkdir -p "${INPUT_DIR}"
    if [ $? -ne 0 ] ; then
        echo "could not make the directory: ${INPUT_DIR}"
        exit 1
    fi
fi
if [ ! -w "${OUTPUT_DIR}" ]; then   # check output directory for write access
    mkdir -p "${OUTPUT_DIR}"
    if [ $? -ne 0 ] ; then
        echo "could not make the directory: ${OUTPUT_DIR}"
        exit 1
    fi
fi

echo ""
echo "This script will first generate some sample audio files"
read -rsp $'Press any key to continue...\n' -n1 key

# generate some audio files
${SCRIPT_PATH}/generate_test_files.sh -o "${INPUT_DIR}/" -t 10 -f 500
$SCRIPT_PATH/generate_test_files.sh -o "${INPUT_DIR}/" -t 100 -f 1000
$SCRIPT_PATH/generate_test_files.sh -o "${INPUT_DIR}/" -t 200 -f 2000

# generate some random image files
touch ${INPUT_DIR}/random_image_file.jpg
touch ${INPUT_DIR}/another_random_image_file.png
touch ${INPUT_DIR}/cover.jpg
touch ${INPUT_DIR}/cover.png

clear
read -rsp $'Press any key to start the tool in terminal mode...\n' -n1 key
clear
${SCRIPT_PATH}/../yad2ogg.sh --input "${INPUT_DIR}/" --output "${OUTPUT_DIR}/" --ALL --verbose --overwrite --copyfile 'cover.jpg'

read -rsp $'Press any key to start the tool in GUI mode...\n' -n1 key
clear
${SCRIPT_PATH}/../yad2ogg.sh --input "${INPUT_DIR}/" --output "${OUTPUT_DIR}/" --ALL --verbose --overwrite --copyfile 'cover.jpg' --gui

# conclusion
echo ""
echo "In the output folder, only the ogg version of the audio files and all the cover.jpg files are placed"

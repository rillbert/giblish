#!/bin/bash
#
# pulls the master branch from origin and then runs giblish
# on the working tree emitting the result to the given destination
# folder
#
# NOTE: This script assumes that all assets referenced from adoc files
# are located in corresponding .../<file>_assets directories
# Ex:
# adoc file .../repo_root/docs/myfile.adoc
# is expected to have an imagesdir directive in its header pointing to:
# .../repo_root/docs/myfile_assets
#
# all ..._assets directories found under SRC_TOP will be copied in full to
# DST_DIR

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

### config section
# set this to the 'resource' folder as expected by the giblish -r flag
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# set this to the publish dir as expected by the giblish -w flag
WEB_ROOT="/giblish"

# display usage message
function usage {
  echo "Usage:"
  echo "  publish_html.sh <dst_dir> [src_top]"
  echo ""
  echo "where"
  echo "  dst_dir      the top dir to where the html will be generated"
}

# abort with non zero exit code
# @param msg  the message to output to user
function die {
  echo "Error! $1"
  exit 1
}

### useful variables
GIT_ROOT=$(git rev-parse --show-toplevel)
[ $? -ne 0 ] && die "You must invoke this from within a git working tree."
SRC_ROOT="${GIT_ROOT}"

# handle user flags
force_remove=''
declare -i nof_flags=0
while getopts 'f' flag; do
  case "${flag}" in
    f) force_remove='true' ;;
    *) print_usage
       exit 1 ;;
  esac
  nof_flags=$((nof_flags + 1))
done
shift $nof_args

# handle user args
if [[ $# < 1 || $# > 2 ]]; then
  usage
  die "Wrong number of input arguments."
fi
DST_HTML=$1
if [[ $nof_args == 2 ]]; then
  SRC_ROOT=$2
fi

# Make the paths absolute
DST_HTML=$(realpath "$1")
[ $? -ne 0 ] && die "Unknown path: $1"
SRC_ROOT=$(realpath "${SRC_ROOT}")
[ $? -ne 0 ] && die "Unknown path: ${SRC_ROOT}"

# update working tree with latest master
echo "Cleaning git repo at..."
git clean -fdx
[ $? -ne 0 ] && die "Could not clean repo"
echo "Pulling updates from origin..."
git pull
[ $? -ne 0 ] && die "Could not pull from origin"

# generate the html from adoc files in repo
echo "Will generate html to: ${DST_HTML} from adoc files found under ${SRC_ROOT}"
if [[ "${force_remove}" ]]; then
  echo "would have run rm -rf ${DST_HTML}..."
fi

giblish -a icons=font -c -r "${RESOURCE_DIR}" -s giblish -w "${WEB_ROOT}" "${SRC_ROOT}" "${DST_HTML}"
[ $? -ne 0 ] && die

# copy assets folders
# do this within subshell so we can use find with '.' notation,
# giving relative paths back
echo "Copying asset folders to destination..."
(
  cd "${SRC_ROOT}"
  find . -name '*_assets' -type d -exec cp -r {} ${DST_HTML}/{} \;
)

#!/bin/bash
#
# pulls the master branch from origin and then runs giblish
# on the working tree emitting the result to the given destination
# folder

### config section
# set this to the 'resource' folder as expected by the giblish -r flag
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# set this to the publish dir as expected by the giblish -w flag
WEB_ROOT="/docs"

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
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SRC_ROOT="${GIT_ROOT}"

# handle user input
if [[ $# < 1 || $# > 2 ]]; then
  usage
  die "Wrong number of input arguments."
fi
if [[ $# == 2 ]]; then
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
exit 1
giblish -a icons=font -c -r "${RESOURCE_DIR}" -w "${WEB_ROOT}" -s rillbert "${SRC_ROOT}" "${DST_HTML}"
[ $? -ne 0 ] && die

# copy assets folders
# do this within subshell so we can use find with '.' notation,
# giving relative paths back
echo "Copying asset folders to destination..."
(
  cd "${SRC_ROOT}"
  find . -name '*_assets' -type d -exec cp -r {} ${DST_HTML}/{} \;
)

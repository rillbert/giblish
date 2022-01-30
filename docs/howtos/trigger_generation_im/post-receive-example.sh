#!/bin/bash
#
# this hook runs a script which, in turn, generates html documentation
# and publishes them to the given destination.
#

# the git refs that should trigger a doc generation at update
TRIGGERING_REFS_REGEX=$'main'

# the staging repo root (where the working tree exists)
STAGING_REPO="/usr/local/git_staging/myrepo_staging"

# The web-server top dir for the published documents
DST_DIR="/var/www/mysite/html/public/docs"

# "true" runs an 'rm -rf' of the destination dir before generating new htmls
CLEAR_DST="false"

echo "post-receive hook running..."

# read the input that git sends to this hook
read oldrev newrev ref

# remove the 'refs/heads/' prefix from the git ref
ref="${ref/refs\/heads\//}"

# filter out refs that are irrelevant for doc generation
if [[ ! "${ref}" =~ "${TRIGGERING_REFS_REGEX}" ]]; then
  echo "Ref '${ref}' received. Doing nothing: only refs matching the regex: /${TRIGGERING_REFS_REGEX}/ will trigger a doc generation."
  exit 0
fi

echo "Document generation triggered by an update to ${ref}."
echo ""

# use a subshell with the correct working dir for the actual doc generation
(
  cd "${STAGING_REPO}"

  # need to unset the GIT_DIR env set by the invoking hook for giblish to work correctly
  unset GIT_DIR

  if [[ "${CLEAR_DST}" -eq "true" ]]; then
    echo "Remove everything under ${DST_DIR}/"
    rm -rf ${DST_DIR}/*
  fi

  # Generate html docs
  giblish --copy-asset-folders "_assets$" -g "${TRIGGERING_REFS_REGEX}" -r scripts/resources -s mystyle . "${DST_DIR}"
)

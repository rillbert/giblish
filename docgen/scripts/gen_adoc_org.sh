#!/bin/bash
# generates the asciidoctor.org docs to a web server
# see usage function for usage

### configuration variables

# the deployment paths needed by giblish when generating the docs
uri_path="/adocorg/with_search"
deployment_dir="/var/www/rillbert_se/adoc/examples/adocorg"

# the cgi bin paths on the deployment server
cgi_dir="/var/www/cgi-bin"

### end of config section

function usage() {
    echo ""
    echo "Generates the asciidoctor.org docs to html using giblish and"
    echo "deploys it to the server given by <ssh_host>."
    echo ""
    echo "NOTE: that you most likely need to tweak the deployment paths within this script"
    echo "to your specific situation. See the doc within the script."
    echo ""
    echo "Usage: "
    echo "  gen_adoc_org <ssh_host>"
    echo ""
    echo "  ssh_host   the ssh host including user name (eg user1@my.webserver.com)"
    echo ""
}

# check input variables
if [ $# -ne 1 ]; then
  echo ""
  echo "ERROR: Wrong number of input arguments !!!"
  usage
  exit 1
fi

# ssh_host="${ssh_user}@${web_server}:"
ssh_host="$1:"
html_doc_target="${ssh_host}${deployment_dir}"
cgi_bin_target="${ssh_host}${cgi_dir}"


# clone the asciidoctor repo
git clone https://github.com/asciidoctor/asciidoctor.org.git

# generate the html docs
giblish -j '^.*_include.*' -m -mp "${deployment_dir}" -w ${uri_path} -g master --index-basename "myindex" asciidoctor.org/docs ./generated_docs

# copy the docs to the web server
scp -r ./generated_docs/* "${html_doc_target}"

# get the path to the search script
search_script="$(dirname $(gem which giblish))/giblish-search.rb"

# copy the script to the cgi-bin on the web server
scp "${search_script}" "${cgi_bin_target}/giblish-search.cgi"

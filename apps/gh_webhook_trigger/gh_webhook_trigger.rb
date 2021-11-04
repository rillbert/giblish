require "sinatra"
require "json"

# giblish -a xrefstyle=basic --copy-asset-folders "_assets$" -g "${TRIGGERING_REFS_REGEX}" -r scripts/resources -s giblish docs "${DST_DIR}"

post "/payload" do
  puts request.body.read
  # push = JSON.parse(request.body.read, symbolized_names: true)
  # puts "JSON from github: #{push.inspect}"
end

require_relative "../subtreeinfobuilder"
require_relative "../node_data_provider"

module Giblish
  # Adds a 'FileHistory' instance to each node's data via dynamic composition.
  # Users down-the-line can then call node.data.history to receive
  # a FileHistory object.
  class AddHistoryPostBuilder
    def initialize(repo_root)
      @git_itf = GitItf.new(repo_root)
    end

    # Called from TreeConverter during post build phase
    def on_postbuild(src_tree, dst_tree, converter)
      current_branch = @git_itf.current_branch

      dst_tree.traverse_preorder do |level, dst_node|
        unless dst_node.leaf?
          # Non-leaf nodes don't have conversion info yet, create NodeDataProvider with history
          if dst_node.data.nil?
            dst_node.data = NodeDataProvider.new(FileHistory.new(current_branch))
          end
          next
        end

        src_node = dst_node.data.src_node
        next unless src_node.pathname.exist?

        # Get the commit history of the doc as an Array of entries
        file_log = FileHistory.new(current_branch)
        @git_itf.file_log(src_node.pathname.to_s).each do |log_entry|
          file_log.history << FileHistory::LogEntry.new(
            log_entry["date"],
            log_entry["author"],
            log_entry["message"],
            log_entry["sha"]
          )
        end

        # Add history provider to existing NodeDataProvider
        dst_node.data.add_provider(file_log)
      end
    end
  end
end

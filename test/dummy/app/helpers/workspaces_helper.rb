module WorkspacesHelper
  def recordings_hierarchy_list(recordings_by_parent, parent_id: nil)
    children = Array(recordings_by_parent[parent_id])
    return "".html_safe if children.empty?

    render FlatPack::Tree::Component.new(compact: true, class: "w-full") do |tree|
      recordings_hierarchy_nodes(tree, recordings_by_parent, parent_id: parent_id)
    end
  end

  private

  def recordings_hierarchy_nodes(tree, recordings_by_parent, parent_id:)
    Array(recordings_by_parent[parent_id]).each do |recording|
      children = Array(recordings_by_parent[recording.id])
      options = {
        label: recording.name,
        href: recording_path(recording),
        expanded: children.any?,
        active: current_page?(recording_path(recording)),
        meta: recording.type_label
      }

      if children.any?
        tree.node(**options) do |branch|
          recordings_hierarchy_nodes(branch, recordings_by_parent, parent_id: recording.id)
        end
      else
        tree.node(**options)
      end
    end
  end
end

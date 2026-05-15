module TreeHelper
  def render_recording_tree_nodes(tree, recordings_by_parent, parent_id: nil)
    Array(recordings_by_parent[parent_id]).each do |recording|
      children = Array(recordings_by_parent[recording.id])
      options = {
        label: recording_tree_label(recording),
        icon: recording_tree_icon(recording),
        expanded: children.any?,
        meta: recording.type_label
      }

      if children.any?
        tree.node(**options) do |branch|
          render_recording_tree_nodes(branch, recordings_by_parent, parent_id: recording.id)
        end
      else
        tree.node(**options.merge(href: recording_path(recording), active: current_page?(recording_path(recording))))
      end
    end
  end

  def recording_tree_icon(recording)
    case recording.recordable_type
    when Workspace.name
      "home"
    when RecordingStudioFolder.name
      "folder"
    else
      "document-text"
    end
  end

  def recording_tree_label(recording)
    recording.name
  end
end

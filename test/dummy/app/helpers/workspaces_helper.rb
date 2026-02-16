module WorkspacesHelper
  def recordings_hierarchy_list(recordings_by_parent, parent_id: nil)
    children = recordings_by_parent[parent_id] || []
    return "".html_safe if children.empty?

    content_tag :ul, class: "list-disc pl-6 space-y-1" do
      safe_join(
        children.map do |recording|
          content_tag :li do
            link = link_to(
              recordable_label(recording.recordable),
              recording_path(recording),
              class: "hover:underline"
            )

            nested = recordings_hierarchy_list(recordings_by_parent, parent_id: recording.id)
            safe_join([ link, nested ])
          end
        end
      )
    end
  end
end

module WorkspacesHelper
  def recordings_hierarchy_list(recordings_by_parent, parent_id: nil)
    children = recordings_by_parent[parent_id] || []
    return "".html_safe if children.empty?

    content_tag :ul, class: "list-disc pl-6 space-y-1" do
      safe_join(
        children.map do |recording|
          content_tag :li do
            link = if recording.recordable_type == "RecordingStudio::AccessBoundary"
              minimum_role = recording.recordable&.minimum_role
              text = minimum_role.present? ? "🔒 Boundary (min: #{minimum_role})" : "🔒 Boundary"
              content_tag(:span, text, class: "rounded bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-700")
            else
              link_to(
                recordable_label(recording.recordable),
                recording_path(recording),
                class: "hover:underline"
              )
            end

            nested = recordings_hierarchy_list(recordings_by_parent, parent_id: recording.id)
            safe_join([ link, nested ])
          end
        end
      )
    end
  end
end

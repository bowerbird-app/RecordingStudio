# frozen_string_literal: true

require_relative "../test_helper"

class HelpersLogicTest < ActiveSupport::TestCase
  test "recordable helpers prefer recordable contracts and summaries" do
    folder = RecordingStudioFolder.create!(name: "Projects")
    comment = RecordingStudioComment.create!(body: "This is a helpful note")

    assert_equal "📁 Projects", ApplicationController.helpers.recordable_name(folder)
    assert_equal "Folder", ApplicationController.helpers.recordable_type_label(folder)
    assert_equal "Projects", ApplicationController.helpers.recordable_title(folder)
    assert_equal "This is a helpful note", ApplicationController.helpers.recordable_summary(comment)
  end

  test "recordings_hierarchy_list renders nested recordings" do
    workspace = Workspace.create!(name: "Workspace")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    child = RecordingStudio::Recording.create!(
      root_recording: root,
      parent_recording: root,
      recordable: RecordingStudioPage.create!(title: "Child Page")
    )

    grouped = {
      nil => [ root ],
      root.id => [ child ]
    }

    helpers = ApplicationController.helpers
    helpers.singleton_class.send(:define_method, :recording_path) { |recording| "/recordings/#{recording.id}" }

    html = helpers.recordings_hierarchy_list(grouped)

    assert_includes html, "Child Page"
    assert_includes html, "list-disc"
  end
end

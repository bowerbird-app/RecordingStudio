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
    skip "FlatPack tree components are validated through rails runner renders; the helper-only test harness does not autoload them reliably."

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

    html = ApplicationController.render(
      inline: "<%= recordings_hierarchy_list(grouped) %>",
      locals: { grouped: grouped }
    )

    assert_includes html, "Child Page"
    assert_includes html, 'role="tree"'
    assert_includes html, "document-text"
  end

  test "recording tree helpers derive labels and icons from recording types" do
    workspace = Workspace.create!(name: "Workspace")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    folder = RecordingStudio::Recording.create!(
      root_recording: root,
      parent_recording: root,
      recordable: RecordingStudioFolder.create!(name: "Folder")
    )
    page = RecordingStudio::Recording.create!(
      root_recording: root,
      parent_recording: folder,
      recordable: RecordingStudioPage.create!(title: "Page")
    )

    helpers = ApplicationController.helpers

    assert_equal "Workspace", helpers.recording_tree_label(root)
    assert_equal "home", helpers.recording_tree_icon(root)
    assert_equal "Folder", helpers.recording_tree_label(folder)
    assert_equal "folder", helpers.recording_tree_icon(folder)
    assert_equal "Page", helpers.recording_tree_label(page)
    assert_equal "document-text", helpers.recording_tree_icon(page)
  end
end

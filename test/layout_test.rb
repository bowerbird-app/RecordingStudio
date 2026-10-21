# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class LayoutTest < Minitest::Test
  def test_default_layout_constant_names_the_shared_layout
    assert_equal "recording_studio/default_layout", RecordingStudio::DEFAULT_LAYOUT
    layout_path = RecordingStudio::Engine.root.join("app/views/layouts/#{RecordingStudio::DEFAULT_LAYOUT}.html.erb")
    assert File.exist?(layout_path)
  end

  def test_resolve_accepts_a_name_nil_or_false
    controller = Object.new

    assert_nil RecordingStudio::Layout.resolve(nil, controller: controller)
    assert_equal false, RecordingStudio::Layout.resolve(false, controller: controller)
    assert_equal "pages", RecordingStudio::Layout.resolve("pages", controller: controller)
  end

  def test_resolve_calls_a_keyword_callable_and_rejects_a_positional_one
    controller = Object.new
    callable = ->(controller:) { controller.object_id.to_s }

    assert_equal controller.object_id.to_s, RecordingStudio::Layout.resolve(callable, controller: controller)
    assert_nil RecordingStudio::Layout.resolve(->(controller:) { controller && nil }, controller: controller)
    assert_equal false, RecordingStudio::Layout.resolve(->(controller:) { controller && false }, controller: controller)

    positional = ->(controller) { controller.class.name }
    error = assert_raises(ArgumentError) { RecordingStudio::Layout.resolve(positional, controller: controller) }
    assert_match(/controller:/, error.message)

    error = assert_raises(ArgumentError) { RecordingStudio::Layout.resolve("pages", controller) }
    assert_match(/controller/, error.message)
  end

  def test_resolve_rejects_a_blank_name_and_a_non_layout_return
    controller = Object.new

    assert_raises(ArgumentError) { RecordingStudio::Layout.resolve("  ", controller: controller) }
    assert_raises(ArgumentError) do
      RecordingStudio::Layout.resolve(->(controller:) { controller && 1 }, controller: controller)
    end
    assert_raises(ArgumentError) { RecordingStudio::Layout.resolve(1, controller: controller) }
  end

  def test_hardcoded_layout_paths_lists_recording_studio_layout_strings
    Dir.mktmpdir do |root|
      controllers = File.join(root, "app", "controllers", "widgets")
      FileUtils.mkdir_p(controllers)
      hardcoded = File.join(controllers, "posts_controller.rb")
      File.write(hardcoded, "class PostsController\n  layout \"recording_studio/default_layout\"\nend\n")
      File.write(
        File.join(controllers, "clean_controller.rb"),
        "class CleanController\n  recording_studio_layout\nend\n"
      )
      File.write(
        File.join(controllers, "action_controller.rb"),
        "class ActionController\n  layout 'recording_studio/action_layout'\nend\n"
      )

      action_controller = File.join(controllers, "action_controller.rb")
      paths = RecordingStudio::Layout.hardcoded_layout_paths(root)

      assert_equal [hardcoded, action_controller].sort, paths.sort
      assert_equal [action_controller], RecordingStudio::Layout.hardcoded_layout_paths(
        root,
        ignore: ["app/controllers/widgets/posts_controller.rb"]
      )
    end
  end

  def test_engine_controllers_do_not_hard_code_a_recording_studio_layout
    assert_empty RecordingStudio::Layout.hardcoded_layout_paths(RecordingStudio::Engine.root)
  end
end

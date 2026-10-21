# frozen_string_literal: true

require "test_helper"

class LayoutResolutionParentController < ActionController::Base
  class_attribute :gem_layout_setting, instance_accessor: true

  recording_studio_layout { gem_layout_setting }
end

class LayoutResolutionChildController < LayoutResolutionParentController
end

class LayoutResolutionOverrideController < LayoutResolutionParentController
  layout "host_pages"
end

class LayoutResolutionNoLayoutController < LayoutResolutionParentController
  layout false
end

class LayoutResolutionTest < ActiveSupport::TestCase
  setup do
    @original_layout = RecordingStudio.configuration.layout
    RecordingStudio.configuration.layout = nil
    LayoutResolutionParentController.gem_layout_setting = nil
  end

  teardown do
    RecordingStudio.configuration.layout = @original_layout
    LayoutResolutionParentController.gem_layout_setting = nil
  end

  test "gem setting wins over core configuration and the default" do
    LayoutResolutionParentController.gem_layout_setting = "gem_pages"
    RecordingStudio.configuration.layout = "core_pages"

    assert_equal "gem_pages", resolved(LayoutResolutionChildController)
  end

  test "a nil gem setting falls through to core configuration" do
    LayoutResolutionParentController.gem_layout_setting = nil
    RecordingStudio.configuration.layout = "core_pages"

    assert_equal "core_pages", resolved(LayoutResolutionChildController)
  end

  test "a nil gem callable falls through to core configuration" do
    seen = nil
    LayoutResolutionParentController.gem_layout_setting = ->(controller:) { controller && nil }
    RecordingStudio.configuration.layout = lambda { |controller:|
      seen = controller
      "core_pages"
    }

    controller = LayoutResolutionChildController.new

    assert_equal "core_pages", controller.recording_studio_resolved_layout
    assert_instance_of LayoutResolutionChildController, seen
  end

  test "nil at every level uses the default layout constant" do
    LayoutResolutionParentController.gem_layout_setting = ->(controller:) { controller && nil }
    RecordingStudio.configuration.layout = ->(controller:) { controller && nil }

    assert_equal RecordingStudio::DEFAULT_LAYOUT, resolved(LayoutResolutionChildController)
    assert_equal RecordingStudio::DEFAULT_LAYOUT, resolved(RecordingStudio::ApplicationController)
  end

  test "false from the gem setting renders with no layout and does not fall through" do
    LayoutResolutionParentController.gem_layout_setting = ->(controller:) { controller && false }
    RecordingStudio.configuration.layout = "core_pages"

    assert_equal false, resolved(LayoutResolutionChildController)
    assert_equal false, rendered_layout(LayoutResolutionChildController)
  end

  test "false from core configuration renders with no layout" do
    LayoutResolutionParentController.gem_layout_setting = nil
    RecordingStudio.configuration.layout = false

    assert_equal false, resolved(LayoutResolutionChildController)
  end

  test "a child controller inherits the parent resolver" do
    LayoutResolutionParentController.gem_layout_setting = "from_parent"

    assert_equal :recording_studio_resolved_layout, LayoutResolutionChildController._layout
    assert_equal "from_parent", resolved(LayoutResolutionParentController)
    assert_equal "from_parent", resolved(LayoutResolutionChildController)
  end

  test "a controller layout string overrides the inherited resolver" do
    LayoutResolutionParentController.gem_layout_setting = "from_parent"
    RecordingStudio.configuration.layout = "core_pages"

    assert_equal "host_pages", LayoutResolutionOverrideController._layout
    assert_equal "host_pages", rendered_layout(LayoutResolutionOverrideController)
  end

  test "layout false on a controller overrides the inherited resolver" do
    LayoutResolutionParentController.gem_layout_setting = "from_parent"

    assert_equal false, LayoutResolutionNoLayoutController._layout
    assert_nil rendered_layout(LayoutResolutionNoLayoutController)
  end

  private

  def resolved(controller_class)
    controller_class.new.recording_studio_resolved_layout
  end

  def rendered_layout(controller_class)
    controller = controller_class.new
    lookup = ActionView::LookupContext.new(controller_class.view_paths)
    controller.send(:_layout, lookup, [:html], [])
  end
end

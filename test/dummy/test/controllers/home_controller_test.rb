# frozen_string_literal: true

require_relative "../test_helper"

class HomeControllerTest < ActiveSupport::TestCase
  test "page header component renders" do
    html = ApplicationController.render(
      inline: <<~ERB
        <%= render FlatPack::PageHeader::Component.new(
          title: "Recording Studio Demo",
          subtitle: "Explore explicit workspace-root recordings, revisions, folders, capability hooks, and events in a demo app with no hidden current workspace.",
          class: "mb-6"
        ) %>
      ERB
    )

    assert_includes html, "Recording Studio Demo"
  end

  test "sidebar header shows RecordingStudio version badge" do
    html = ApplicationController.render(partial: "layouts/flat_pack/sidebar")

    assert_includes html, "v#{RecordingStudio::VERSION}"
    refute_includes html, "v#{FlatPack::VERSION}"
  end
end

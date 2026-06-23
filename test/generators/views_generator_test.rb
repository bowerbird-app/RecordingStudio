# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/recording_studio/views/views_generator"

class ViewsGeneratorTest < Rails::Generators::TestCase
  tests RecordingStudio::Generators::ViewsGenerator
  destination File.expand_path("../tmp/views_generator", __dir__)

  def setup
    prepare_destination
  end

  def test_generates_resource_templates
    run_generator(["post"])

    assert_file "app/views/posts/index.html.erb", /recording_studio_page_nav\(title: "Posts"\)/
    assert_file "app/views/posts/index.html.erb", /FlatPack::PageTitle::Component/
    assert_file "app/views/posts/show.html.erb", /content_for :top_nav_left do/
    assert_file "app/views/posts/show.html.erb", /recording_studio\/shared\/page_nav/
    assert_file "app/views/posts/show.html.erb", /content_for :top_nav_center do/
    assert_file "app/views/posts/new.html.erb", /render "form", post: @post/
    assert_file "app/views/posts/new.html.erb", /content_for :top_nav_center do/
    assert_file "app/views/posts/edit.html.erb", /render "form", post: @post/
    assert_file "app/views/posts/edit.html.erb", /content_for :top_nav_center do/
    assert_file "app/views/posts/_form.html.erb", /FlatPack::TextInput::Component/
    assert_file "app/views/posts/_form.html.erb", /FlatPack::Button::Component/
  end
end

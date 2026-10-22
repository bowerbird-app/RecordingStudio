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

    assert_file "app/views/posts/index.html.erb", /content_for :title, "Posts"/
    assert_file "app/views/posts/index.html.erb", /content_for :subtitle, "Replace this list/
    assert_file "app/views/posts/index.html.erb", /flat_pack_page_nav/
    assert_file "app/views/posts/show.html.erb", /flat_pack_page_nav\(/
    assert_file "app/views/posts/show.html.erb", /back_href: posts_path/
    assert_file "app/views/posts/new.html.erb", /render "form", post: @post/
    assert_file "app/views/posts/new.html.erb", /back_href: posts_path/
    assert_file "app/views/posts/edit.html.erb", /render "form", post: @post/
    assert_file "app/views/posts/edit.html.erb", /back_href: post_path\(@post\)/
    assert_file "app/views/posts/_form.html.erb", /FlatPack::TextInput::Component/
    assert_file "app/views/posts/_form.html.erb", /FlatPack::Button::Component/
    %w[index show new edit].each do |action|
      source = File.read(File.join(destination_root, "app/views/posts/#{action}.html.erb"))
      refute_includes source, "recording_studio_page_nav"
      refute_includes source, "PageTitle"
    end
  end
end

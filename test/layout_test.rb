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
        "class ActionController\n  layout 'recording_studio/library'\nend\n"
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

class DefaultBackgroundConfigurationTest < ActiveSupport::TestCase
  EXPECTED_SVG = <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 900" width="1280" height="900">
      <defs>
        <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#dbeafe"/>
          <stop offset="50%" stop-color="#ede9fe"/>
          <stop offset="100%" stop-color="#fce7f3"/>
        </linearGradient>
      </defs>
      <rect width="1280" height="900" fill="url(#bg)"/>
      <circle cx="220" cy="180" r="260" fill="#93c5fd" fill-opacity="0.45"/>
      <circle cx="1040" cy="700" r="320" fill="#c4b5fd" fill-opacity="0.45"/>
    </svg>
  SVG

  test "configuration defaults to the built-in background asset" do
    configuration = RecordingStudio::Configuration.new

    assert_equal "recording_studio/default_background.svg", RecordingStudio::DEFAULT_BACKGROUND_IMAGE
    assert_equal RecordingStudio::DEFAULT_BACKGROUND_IMAGE, configuration.default_background_image
    assert_equal RecordingStudio::DEFAULT_BACKGROUND_IMAGE, RecordingStudio.configuration.default_background_image

    asset = RecordingStudio::Engine.root.join("app/assets/images", RecordingStudio::DEFAULT_BACKGROUND_IMAGE)
    assert_equal EXPECTED_SVG, File.read(asset)
  end

  test "configure and merge! share one host background across readers" do
    original = RecordingStudio.configuration.default_background_image
    configuration = RecordingStudio::Configuration.new
    configuration.merge!("default_background_image" => "/from-yaml.webp")

    assert_equal "/from-yaml.webp", configuration.default_background_image

    RecordingStudio.configure { |config| config.default_background_image = "/host-bg.webp" }

    assert_equal "/host-bg.webp", RecordingStudio.configuration.default_background_image
  ensure
    RecordingStudio.configuration.default_background_image = original
  end

  test "asset initializer registers the image path and sprockets precompile" do
    initializer = RecordingStudio::Engine.initializers.find { |item| item.name == "recording_studio.assets" }
    assets = Struct.new(:paths, :precompile).new([], [])
    app = Struct.new(:config).new(Struct.new(:assets).new(assets))

    initializer.run(app)

    images = RecordingStudio::Engine.root.join("app/assets/images").to_s
    assert_includes assets.paths, images
    assert_includes assets.precompile, RecordingStudio::DEFAULT_BACKGROUND_IMAGE

    initializer.run(app)

    assert_equal 1, assets.paths.count(images)
    assert_equal 1, assets.precompile.count(RecordingStudio::DEFAULT_BACKGROUND_IMAGE)
  end

  test "asset initializer ignores a host with no asset config" do
    initializer = RecordingStudio::Engine.initializers.find { |item| item.name == "recording_studio.assets" }
    app = Struct.new(:config).new(Object.new)

    initializer.run(app)

    refute app.config.respond_to?(:assets)
  end

  test "the booted host can resolve the built-in asset" do
    images = RecordingStudio::Engine.root.join("app/assets/images").to_s

    assert_includes Rails.application.config.assets.paths.map(&:to_s), images
    resolved = ActionController::Base.helpers.asset_path(RecordingStudio::DEFAULT_BACKGROUND_IMAGE)

    assert_includes resolved, "recording_studio/default_background"
  end
end

class LayoutBackgroundHelperTest < ActionView::TestCase
  include RecordingStudio::LayoutHelper

  setup do
    @original = RecordingStudio.configuration.default_background_image
  end

  teardown do
    RecordingStudio.configuration.default_background_image = @original
  end

  test "default background helper reads the host configuration" do
    assert_equal RecordingStudio::DEFAULT_BACKGROUND_IMAGE, recording_studio_default_background_image

    RecordingStudio.configuration.default_background_image = "  /host-bg.webp  "

    assert_equal "/host-bg.webp", recording_studio_default_background_image
  end

  test "opting in stores the configured background" do
    opt_ins = [
      -> { recording_studio_background_image },
      -> { recording_studio_background_image(true) },
      -> { recording_studio_background_image(:default) }
    ]
    opt_ins.each do |opt_in|
      @view_flow = ActionView::OutputFlow.new
      assert_nil opt_in.call
      assert_equal RecordingStudio::DEFAULT_BACKGROUND_IMAGE, content_for(:background_image)
    end

    @view_flow = ActionView::OutputFlow.new
    RecordingStudio.configuration.default_background_image = "/host-bg.webp"
    recording_studio_background_image(true)

    assert_equal "/host-bg.webp", content_for(:background_image)
  end

  test "a custom path replaces the default for that call" do
    result = recording_studio_background_image("/custom-page-bg.jpg")

    assert_nil result
    assert_equal "/custom-page-bg.jpg", content_for(:background_image)
  end

  test "false nil and blank store nothing" do
    [false, nil, "", " "].each do |value|
      @view_flow = ActionView::OutputFlow.new
      assert_nil recording_studio_background_image(value)
      assert_predicate content_for(:background_image), :blank?
    end
  end
end

class LayoutBackgroundProbeController < ApplicationController
  recording_studio_layout

  TEMPLATES = {
    "helper" => "<% recording_studio_background_image %>",
    "true" => "<% recording_studio_background_image(true) %>",
    "symbol" => "<% recording_studio_background_image(:default) %>",
    "content_true" => "<% content_for(:background_image) { 'true' } %>",
    "content_default" => "<% content_for(:background_image) { 'default' } %>",
    "content_false" => "<% content_for(:background_image) { 'false' } %>",
    "custom" => "<% recording_studio_background_image('/custom-page-bg.jpg') %>",
    "false" => "<% recording_studio_background_image(false) %>",
    "nil" => "<% recording_studio_background_image(nil) %>",
    "blank" => "<% recording_studio_background_image('') %>",
    "omit" => "<p>Plain page</p>"
  }.freeze

  def show
    render inline: TEMPLATES.fetch(params[:mode]), layout: true
  end
end

class LayoutBackgroundRenderTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Background User")
    sign_in_as(@user)
    @original = RecordingStudio.configuration.default_background_image
  end

  teardown do
    RecordingStudio.configuration.default_background_image = @original
  end

  test "demo page opts into the built-in background" do
    get layout_demo_default_background_path, headers: modern_headers

    assert_response :success
    assert_default_background
  end

  test "opting in renders the built-in background inside layout.background" do
    %w[helper true symbol content_true content_default].each do |mode|
      get_probe(mode)

      assert_response :success
      assert_default_background
    end
  end

  test "a host override changes the opt-in background" do
    RecordingStudio.configuration.default_background_image = "/host-bg.webp"

    %w[helper true symbol content_true].each do |mode|
      get_probe(mode)

      assert_response :success
      assert_background_src "/host-bg.webp"
    end

    sign_in_as(@user)
    get layout_demo_default_background_path, headers: modern_headers

    assert_response :success
    assert_background_src "/host-bg.webp"
  end

  test "a custom url overrides the default for that page" do
    RecordingStudio.configuration.default_background_image = "/host-bg.webp"
    get_probe("custom")

    assert_response :success
    assert_background_src "/custom-page-bg.jpg"
  end

  test "false nil blank and an omitted helper render no background" do
    %w[false nil blank omit content_false].each do |mode|
      get_probe(mode)

      assert_response :success
      assert_no_background
    end

    sign_in_as(@user)
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_no_background
  end

  private

  def get_probe(mode)
    sign_in_as(@user)
    with_routing do |routes|
      routes.draw { get "/layout_background_probe", to: "layout_background_probe#show" }
      get "/layout_background_probe", params: { mode: mode }, headers: modern_headers
    end
  end

  def assert_default_background
    expected = ActionController::Base.helpers.asset_path(RecordingStudio::DEFAULT_BACKGROUND_IMAGE)
    assert_background_src expected
  end

  def assert_background_src(src)
    assert_select "[data-flat-pack-layout-background='true'].fp-layout-main .fp-backdrop[aria-hidden='true']", count: 1
    assert_select ".fp-backdrop-media img[alt=''][loading='lazy'][src='#{src}']", count: 1
  end

  def assert_no_background
    assert_select "[data-flat-pack-layout-background]", count: 0
    assert_select ".fp-backdrop", count: 0
    assert_select ".fp-backdrop-media img", count: 0
  end
end

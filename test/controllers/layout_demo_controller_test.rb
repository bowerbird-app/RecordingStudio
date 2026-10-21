# frozen_string_literal: true

require "test_helper"

class LayoutDemoControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Layout Demo User")
    sign_in_as(@user)
  end

  test "show renders default layout with page nav" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Default Layout Demo"
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "body[data-theme='rounded']", count: 1
    assert_select "meta[name='recording-studio-demo'][content='default-layout']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "nav[data-flat-pack--page-nav-fallback-url-value='#{workspaces_path}']", count: 1
    assert_select "nav button[aria-label='Go back']", count: 1
    assert_select "nav a[aria-label='Go back']", count: 0
    assert_select "a[href='#{workspaces_path}'][aria-label='Close demo']", count: 1
    assert_select "nav .ml-auto a[href='#{new_workspace_path}']", count: 1
    assert_includes @response.body, I18n.t("recording_studio.core.navigation.go_back")
    assert_includes @response.body, "Go back"
    assert_includes @response.body, "Close demo"

    assert_includes @response.body, "Create workspace"
    assert_not_includes @response.body, "flat-pack--sidebar-group"

    # SEO / OpenGraph meta tags
    assert_select "meta[property='og:title'][content='Default Layout Demo']", count: 1
    assert_select "meta[property='og:type'][content='website']", count: 1
    assert_select "meta[name='description'][content*='SEO']", count: 1
    assert_select "meta[property='og:image'][content='https://example.com/og-image.png']", count: 1
    assert_select "meta[property='og:site_name'][content='Custom App Name']", count: 1
    assert_select "meta[property='og:description'][content*='SEO']", count: 1
  end

  test "show falls back to configured app_name when no title content_for is set" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Default Layout Demo"
    assert_select "meta[property='og:site_name'][content='Custom App Name']", count: 1
  end

  test "non-FlatPack page nav fallback renders literal english" do
    page_nav_component = FlatPack::PageNav::Component
    FlatPack::PageNav.send(:remove_const, :Component)

    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "#recording-studio-back-button", count: 1
    assert_includes @response.body, 'aria-label="Go back"'
    assert_includes @response.body, "Close demo"
    assert_not_includes @response.body, "flat-pack--page-nav"
  ensure
    FlatPack::PageNav.const_set(:Component, page_nav_component) if page_nav_component
  end

  test "pure HTML page nav fallback renders default Close english" do
    page_nav_component = FlatPack::PageNav::Component
    button_component = FlatPack::Button::Component
    FlatPack::PageNav.send(:remove_const, :Component)
    FlatPack::Button.send(:remove_const, :Component)

    get layout_demo_chrome_defaults_path, headers: modern_headers

    assert_response :success
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "#recording-studio-back-button", count: 0
    assert_includes @response.body, "Go back"
    assert_includes @response.body, "Close"
    assert_not_includes @response.body, "Close demo"
  ensure
    FlatPack::PageNav.const_set(:Component, page_nav_component) if page_nav_component
    FlatPack::Button.const_set(:Component, button_component) if button_component
  end

  test "default layout template keeps the host contract slots, assets, and alerts" do
    source = File.read(
      RecordingStudio::Engine.root.join("app/views/recording_studio/shared/_default_layout.html.erb")
    )
    %w[
      head title body_theme seo_description seo_image
      page_nav_anchor_url page_nav_anchor_icon page_nav_anchor_label
      page_nav_back_icon page_nav_back_label page_nav_back_style
      page_nav_back_size page_nav_back_url page_nav_right
    ].each { |slot| assert_includes source, slot }
    assert_includes source, "flat_pack/variables"
    assert_includes source, "flat_pack/rich_text"
    assert_includes source, "FlatPack::Alert::Component"

    host_shell = File.read(Rails.root.join("app/views/layouts/application.html.erb"))
    assert_includes host_shell, "FlatPack::SidebarLayout::Component"
    assert_includes host_shell, "FlatPack::Alert::Component"
    assert_includes host_shell, "flat_pack/variables"
  end

  test "default layout renders flatpack assets, alerts, and content_for slots" do
    get layout_demo_contract_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "link[rel=stylesheet][href*='flat_pack/variables']", minimum: 1
    assert_select "link[rel=stylesheet][href*='flat_pack/rich_text']", minimum: 1
    assert_includes @response.body, "Saved the page"
    assert_includes @response.body, "Could not save the page"
    assert_select "title", text: "Default Layout Demo"
    assert_select "meta[name='recording-studio-demo'][content='default-layout']", count: 1
    assert_not_includes @response.body, "flat-pack--sidebar-layout"
  end
end

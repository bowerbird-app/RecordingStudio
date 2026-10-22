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
    assert_select "nav a[href='#{new_workspace_path}']", count: 0
    assert_includes @response.body, "Go back"
    assert_includes @response.body, "Close demo"
    assert_not_includes @response.body, "flat-pack--sidebar-group"

    # SEO / OpenGraph meta tags
    assert_select "meta[property='og:title'][content='Default Layout Demo']", count: 1
    assert_select "meta[property='og:type'][content='website']", count: 1
    assert_select "meta[name='description'][content*='OpenGraph']", count: 1
    assert_select "meta[property='og:image']", count: 0
    assert_select "meta[property='og:site_name'][content='Custom App Name']", count: 1
    assert_select "meta[property='og:description'][content*='OpenGraph']", count: 1
  end

  test "show renders the title then the page actions" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "h1", text: "Default Layout Demo"
    assert_includes @response.body, "Title, subtitle, then the page actions."
    assert_select "a[href='#{new_workspace_path}']", text: "Add workspace"
    assert_select "a[href='#{workspaces_path}']", text: "Browse workspaces"
    main = @response.body.split("<main", 2).last
    assert_operator main.index("Default Layout Demo"), :<, main.index("Add workspace")
    assert_operator main.index("Add workspace"), :<, main.index("Browse workspaces")
    refute_includes @response.body, "PageNav above direct page content"
  end

  test "show falls back to configured app_name when no title content_for is set" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Default Layout Demo"
    assert_select "meta[property='og:site_name'][content='Custom App Name']", count: 1
  end

  test "default layout template keeps the host contract slots, assets, and alerts" do
    source = File.read(
      RecordingStudio::Engine.root.join("app/views/recording_studio/shared/_default_layout.html.erb")
    )
    %w[head title seo_description].each { |slot| assert_includes source, slot }
    %w[
      body_theme seo_image page_nav_back_url page_nav_back_label
      page_nav_anchor_url page_nav_anchor_label page_nav_right
      recording_studio_page_nav return_to with_close fallback_url
      recording-studio-back-button history.back
    ].each { |slot| refute_includes source, slot }
    refute_includes source, "defined?(FlatPack"
    %w[
      flat_pack_page_nav_tag page_actions(:header) with_back
      flat_pack/variables flat_pack/rich_text
      FlatPack::PageNav::Component FlatPack::PageTitle::Component
      content_for(:subtitle) FlatPack::Alert::Component
    ].each { |piece| assert_includes source, piece }

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

  test "default back renders when nothing is registered and there is no return_to" do
    get layout_demo_plain_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Plain Layout"
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "nav button[aria-label='Go back']", count: 1
    assert_select "nav[data-controller='flat-pack--page-nav']", count: 1
    assert_select "nav[data-flat-pack--page-nav-fallback-url-value]", count: 0
    assert_select "a[aria-label='Close']", count: 0
  end

  test "return_to fills the anchor when the view registers no page nav" do
    get layout_demo_plain_path, params: { return_to: workspaces_path }, headers: modern_headers

    assert_response :success
    assert_select "nav button[aria-label='Go back']", count: 1
    assert_select "nav[data-flat-pack--page-nav-fallback-url-value='#{workspaces_path}']", count: 1
    assert_select "a[href='#{workspaces_path}'][aria-label='Close']", count: 1
  end

  test "an unsafe return_to does not add an anchor" do
    get layout_demo_plain_path, params: { return_to: "https://evil.example/phish" }, headers: modern_headers

    assert_response :success
    assert_select "nav button[aria-label='Go back']", count: 1
    assert_select "nav[data-flat-pack--page-nav-fallback-url-value]", count: 0
    assert_select "a[aria-label='Close']", count: 0
    assert_select "nav", text: /evil\.example/, count: 0
  end

  test "a registered anchor wins over return_to" do
    get layout_demo_path, params: { return_to: root_path }, headers: modern_headers

    assert_response :success
    assert_select "a[href='#{workspaces_path}'][aria-label='Close demo']", count: 1
    assert_select "a[href='#{root_path}'][aria-label='Close']", count: 0
  end
end

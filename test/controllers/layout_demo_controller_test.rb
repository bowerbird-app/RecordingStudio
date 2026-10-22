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

  test "show renders page buttons in the top nav, then the title" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "h1", text: "Default Layout Demo"
    assert_includes @response.body, "On a phone, page buttons fold into the menu."
    assert_select "header[data-controller='flat-pack--top-nav']", count: 1
    assert_select "[data-flat-pack-top-nav-section='left'][data-flat-pack-top-nav-collapsible='true']", count: 1
    right = "[data-flat-pack-top-nav-section='right']"
    assert_select "#{right} a[href='#{new_workspace_path}'][data-fp-style='secondary']", text: "Add workspace"
    assert_select "#{right} a[href='#{workspaces_path}'][data-fp-style='ghost']", text: "Browse workspaces"
    assert_select "[data-fp-page-nav='menu']", count: 0
    assert_select "nav a[href='#{new_workspace_path}']", count: 0
    main = @response.body.split("<main", 2).last
    assert_operator main.index("Add workspace"), :<, main.index("Default Layout Demo")
    assert_operator main.index("Browse workspaces"), :<, main.index("Default Layout Demo")
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
      recording_studio_page_nav return_to with_close fallback_url recording-studio-back-button history.back
    ].each { |slot| refute_includes source, slot }
    refute_includes source, "defined?(FlatPack"
    refute_includes source, "place: :menu"
    %w[
      with_back FlatPack::PageNav page_actions page_action render_page_nav(:header) flex-wrap justify-between
      html_safe always_display fp-page-nav--desktop
    ].each { |slot| refute_includes source, slot }
    %w[
      flat_pack_page_nav_tag render_page_nav(:top_nav) FlatPack::TopNav::Component nav.left nav.right
      javascript_importmap_tags flat_pack/variables flat_pack/application flat_pack/rich_text
      FlatPack::PageTitle::Component content_for(:subtitle) FlatPack::Alert::Component
    ].each { |piece| assert_includes source, piece }
    host_shell = File.read(Rails.root.join("app/views/layouts/application.html.erb"))
    shell_pieces = %w[FlatPack::SidebarLayout::Component FlatPack::Alert::Component]
    shell_pieces += %w[flat_pack/variables flat_pack/application]
    shell_pieces.each { |piece| assert_includes host_shell, piece }
  end

  test "dummy tailwind does not redefine Flatpack color tokens" do
    source = File.read(Rails.root.join("app/assets/tailwind/application.css"))

    refute_match(/--color-primary\s*:/, source)
    refute_match(/--color-fp-/, source)
    refute_match(/--shadow-fp-/, source)
    refute_match(/0\.375rem/, source)
    assert_match(/--radius-md:\s*0\.5rem/, source)
  end

  test "dummy tailwind scans the installed flatpack components and helpers" do
    css = Rails.root.join("app/assets/tailwind/application.css")
    base = css.dirname
    sources = File.read(css).scan(/@source "([^"]+)"/).flatten
    flatpack = sources.map { |entry| base.join(entry).cleanpath }.select { |path| path.to_s.include?("/flatpack-") }

    assert(flatpack.any? { |path| path.directory? && path.to_s.end_with?("/app/components") })
    assert(flatpack.any? { |path| path.directory? && path.to_s.end_with?("/app/helpers") })
    refute_includes File.read(css), "usr/local/bundle"
  end

  test "dummy cards keep default slot padding" do
    offenders = Rails.root.glob("app/views/**/*.erb").select { |path| File.read(path).include?("padding: :none") }
    names = offenders.map { |path| path.relative_path_from(Rails.root).to_s }

    assert_empty names
  end

  test "default layout renders flatpack assets, alerts, and content_for slots" do
    get layout_demo_contract_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "link[rel=stylesheet][href*='flat_pack/variables']", minimum: 1
    assert_select "link[rel=stylesheet][href*='flat_pack/application']", minimum: 1
    assert_select "link[rel=stylesheet][href*='flat_pack/rich_text']", minimum: 1
    assert_includes @response.body, "Saved the page"
    assert_includes @response.body, "Could not save the page"
    assert_select "title", text: "Default Layout Demo"
    assert_select "meta[name='recording-studio-demo'][content='default-layout']", count: 1
    assert_not_includes @response.body, "flat-pack--sidebar-layout"
  end

  test "nothing registered and no return_to renders no page nav" do
    get layout_demo_plain_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Plain Layout"
    assert_select "h1", text: "Plain Layout"
    assert_select "nav[aria-label='Page navigation']", count: 0
    assert_select "a[aria-label='Close']", count: 0
    assert_select "[data-controller='flat-pack--top-nav']", count: 0
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
    assert_select "nav[aria-label='Page navigation']", count: 0
    assert_select "a[aria-label='Close']", count: 0
    assert_select "a[href*='evil.example']", count: 0
  end

  test "a registered anchor wins over return_to" do
    get layout_demo_path, params: { return_to: root_path }, headers: modern_headers

    assert_response :success
    assert_select "a[href='#{workspaces_path}'][aria-label='Close demo']", count: 1
    assert_select "a[href='#{root_path}'][aria-label='Close']", count: 0
  end
end

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
    assert_select "html[data-theme=rounded] body[data-recording-studio-default-layout=true]", count: 1
    assert_select "body[data-theme]", count: 0
    assert_select "meta[name='recording-studio-demo'][content='default-layout']", count: 1
    assert_select "[data-fp-page-layout-width=default][data-fp-page-layout-top-nav-width=content]", count: 1
    assert_select "[data-flat-pack-content-scroll=below] header.fp-top-nav[data-fp-top-nav-padding=none]", count: 1
    assert_select "header nav[aria-label='Page navigation']", count: 1
    assert_select "nav[data-flat-pack--page-nav-fallback-url-value='#{workspaces_path}']", count: 1
    assert_select "nav button[aria-label='Go back'][data-fp-style=default][class*='button-round-border-radius']", count: 1
    assert_select "nav a[aria-label='Go back']", count: 0
    assert_select "a[href='#{workspaces_path}'][aria-label='Close demo'][data-fp-style=default][class*='button-round-border-radius']", count: 1
    assert_select "[data-flat-pack--top-nav-target='toggle']", count: 0
    assert_select "header .fp-button-group-menu[data-variant=outlined]", count: 1
    assert_select "header .fp-button-group-menu__row.fp-button-group--outlined a[data-fp-style=ghost]", minimum: 1
    assert_select "header a[data-fp-style=primary]", count: 0
    assert_select "header .fp-button-group-menu__trigger", count: 1
    assert_registered_page_action(new_workspace_path, "Create workspace")
    assert_select "main .fp-button-group-menu", count: 0
    assert_includes @response.body, "Go back"
    assert_includes @response.body, "Close demo"
    assert_includes @response.body, "Create workspace"
    assert_not_includes @response.body, "flat-pack--sidebar-group"
  end

  test "show publishes open graph tags from the layout" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "meta[property='og:title'][content='Default Layout Demo']", count: 1
    assert_select "meta[property='og:type'][content='website']", count: 1
    assert_select "meta[name='description'][content*='SEO']", count: 1
    assert_select "meta[property='og:image']", count: 0
    assert_select "meta[property='og:site_name'][content='Custom App Name']", count: 1
    assert_select "meta[property='og:description'][content*='SEO']", count: 1
  end

  test "show falls back to configured app_name when no title content_for is set" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Default Layout Demo"
    assert_select "meta[property='og:site_name'][content='Custom App Name']", count: 1
  end

  test "default layout template keeps the host contract slots, assets, and alerts" do
    source = default_layout_source
    %w[head title subtitle seo_description].each { |slot| assert_includes source, slot }
    removed = %w[
      body_theme seo_image page_nav_right page_nav_back_url page_nav_anchor_url
      recording_studio_page_nav mobile_actions: config.page_nav_styles render_page_nav
      FlatPack::PageNavStyles defined?(FlatPack recording-studio-back-button history.back
    ]
    removed.each { |snippet| refute_includes source, snippet }
    kept = [
      "flat_pack_page_nav_tag", "page_nav_button_group", "collapse: :menu", "padding: :none",
      "variant: :outlined", "style: :ghost",
      "FlatPack::PageLayout::Component",
      "FlatPack::TopNav::Component", "FlatPack::PageTitle::Component", "FlatPack::Alert::Component",
      "flat_pack/variables", "flat_pack/application", "flat_pack/rich_text",
      "<html data-theme=\"rounded\">"
    ]
    kept.each { |snippet| assert_includes source, snippet }
    refute_includes source, "PageNavRoleStyles::SOLID"
    refute_includes source, "floating_top_nav"
    refute_includes source, "mobile_menu"
    refute_includes source, "data-recording-studio-default-layout=\"true\" data-theme"
  end

  test "default layout loads flatpack before the host tailwind sheet" do
    source = default_layout_source

    assert_includes source, "viewport-fit=cover"
    assert_includes source, "gap: :lg"
    refute_includes source, 'class: "mb-4"'
    assert source.index("flat_pack/variables") < source.index("flat_pack/application")
    assert source.index("flat_pack/application") < source.index("flat_pack/rich_text")
    assert source.index("flat_pack/rich_text") < source.index('stylesheet_link_tag "tailwind"')
  end

  test "host shell stays on the sidebar layout" do
    host_shell = File.read(Rails.root.join("app/views/layouts/application.html.erb"))

    assert_includes host_shell, "FlatPack::SidebarLayout::Component"
    assert_includes host_shell, "FlatPack::Alert::Component"
    assert_includes host_shell, "FlatPack::SkipLink::Component"
    assert_includes host_shell, "FlatPack::Grid::Component"
    assert_includes host_shell, "gap: :lg"
    assert_includes host_shell, "fp-layout-content"
    assert_includes host_shell, 'id="main"'
    assert_includes host_shell, "viewport-fit=cover"
    assert_includes host_shell, "flat_pack/variables"
    assert_includes host_shell, "flat_pack/application"
    assert_includes host_shell, "page_nav_button_group"
    assert_includes host_shell, "<html data-theme=\"rounded\">"
    assert host_shell.index("flat_pack/variables") < host_shell.index("flat_pack/application")
    assert host_shell.index("flat_pack/rich_text") < host_shell.index('stylesheet_link_tag "tailwind"')
    refute_match(/<body[^>]*data-theme/, host_shell)
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
    assert_select ".mb-4", text: /Saved the page/, count: 0
    assert_select ".mb-4", text: /Could not save the page/, count: 0
    assert_select ".grid.gap-6", minimum: 1
    assert_select "title", text: "Default Layout Demo"
    assert_select "meta[name='recording-studio-demo'][content='default-layout']", count: 1
    assert_not_includes @response.body, "flat-pack--sidebar-layout"
  end

  private

  def default_layout_source
    File.read(RecordingStudio::Engine.root.join("app/views/recording_studio/shared/_default_layout.html.erb"))
  end

  def assert_registered_page_action(href, text)
    assert_select "header .fp-button-group-menu__row a[href='#{href}']", text: text, count: 1
    assert_select "header .fp-button-group-menu__panel a[href='#{href}']", text: text, count: 1
  end
end

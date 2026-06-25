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
    assert_select "a[href='#{workspaces_path}']", count: 1

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
end

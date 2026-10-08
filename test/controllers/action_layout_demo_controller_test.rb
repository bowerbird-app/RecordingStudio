# frozen_string_literal: true

require "test_helper"

class ActionLayoutDemoControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Action Layout Demo User")
    sign_in_as(@user)
  end

  test "show renders action layout with top nav slots and seo" do
    get action_layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Action Layout Demo"
    assert_select "body[data-recording-studio-action-layout='true']", count: 1
    assert_select "body[data-theme='rounded']", count: 1
    assert_select "meta[name='recording-studio-demo'][content='action-layout']", count: 1
    assert_select "header.fp-top-nav.mx-auto.w-full.max-w-5xl.px-6", count: 1
    assert_select "nav[aria-label='Action page navigation']", count: 1
    assert_select "a[href='#{layout_demo_path}']", count: 1
    assert_includes @response.body, "Action Layout Demo"
    assert_includes @response.body, "Workspaces"

    assert_select "meta[property='og:title'][content='Action Layout Demo']", count: 1
    assert_select "meta[name='description'][content*='action layout']", count: 1
    assert_select "meta[property='og:image'][content='https://example.com/action-og-image.png']", count: 1
  end
end

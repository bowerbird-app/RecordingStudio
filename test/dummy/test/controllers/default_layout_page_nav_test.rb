# frozen_string_literal: true

require_relative "../test_helper"

class DefaultLayoutPageNavTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "page-nav@example.com", admin: true)
    sign_in_as(@user)
  end

  test "root layout demo omits back when page_nav_back_url is absent" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-theme='rounded']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "a[aria-label='Close demo'][href=?]", workspaces_path, count: 1
    assert_select "[aria-label='Go back']", count: 0
    assert_select "[data-action='click->flat-pack--page-nav#back']", count: 0
  end

  test "child new workspace shows back linked to page_nav_back_url" do
    get new_workspace_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-theme='rounded']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "a[aria-label='Workspaces'][href=?]", workspaces_path, count: 1
    assert_select "[data-action='click->flat-pack--page-nav#back']", count: 0
  end
end

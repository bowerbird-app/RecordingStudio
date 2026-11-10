# frozen_string_literal: true

require_relative "../test_helper"

class PageNavLeftTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Page Nav Left")
    sign_in_as(@user)
  end

  test "left slot alone draws the top nav with the mark in nav.left" do
    get layout_demo_page_nav_left_path, headers: modern_headers

    assert_response :success
    assert_select "header.fp-top-nav", count: 1
    assert_select "header .fp-top-nav__left > img[src='/icon.png'][alt='']", count: 1
    assert_select "header .fp-top-nav__left > a[aria-label='Studio'][href='#{root_path}']", text: "Studio", count: 1
    assert_select "header .fp-top-nav__left > *", count: 2
    assert_select "header .fp-top-nav__left nav[aria-label='Page navigation']", count: 0
    assert_select "nav button[aria-label='Go back']", count: 0
    assert_select "header .fp-button-group-menu", count: 0
  end

  test "content_for left slot draws the same mark" do
    get layout_demo_page_nav_left_content_for_path, headers: modern_headers

    assert_response :success
    assert_select "header.fp-top-nav", count: 1
    assert_select "header .fp-top-nav__left > a[aria-label='Studio'][href='#{root_path}']", text: "Studio", count: 1
    assert_select "nav button[aria-label='Go back']", count: 0
    assert_select "header .fp-button-group-menu", count: 0
  end

  test "left slot sits before the back row" do
    get layout_demo_page_nav_left_with_back_path, headers: modern_headers

    assert_response :success
    assert_select "header .fp-top-nav__left > img[src='/icon.png']", count: 1
    assert_select "header .fp-top-nav__left > a[aria-label='Studio'][href='#{root_path}']", text: "Studio", count: 1
    assert_select "header .fp-top-nav__left > nav[aria-label='Page navigation']", count: 1
    assert_select "header .fp-top-nav__left > *", count: 3

    left = css_select("header .fp-top-nav__left").first.to_html
    assert_operator left.index("/icon.png"), :<, left.index("Studio")
    assert_operator left.index("Studio"), :<, left.index("Page navigation")
  end

  test "pages that skip the left slot keep the back row alone" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "header .fp-top-nav__left a[aria-label='Studio']", count: 0
    assert_select "header .fp-top-nav__left img[src='/icon.png']", count: 0
    assert_select "header .fp-top-nav__left > nav[aria-label='Page navigation']", count: 1
    assert_select "header .fp-top-nav__left > *", count: 1
  end

  test "home links to the left nav demo" do
    get root_path, headers: modern_headers

    assert_response :success
    assert_select ".fp-button-group-menu__row a[href='#{layout_demo_page_nav_left_with_back_path}']", text: "Left nav demo", count: 1
  end
end

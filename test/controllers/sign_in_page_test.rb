# frozen_string_literal: true

require "test_helper"

class SignInPageTest < ActionDispatch::IntegrationTest
  test "sign in page renders with the current card styles" do
    get new_user_session_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Log in"
  end
end

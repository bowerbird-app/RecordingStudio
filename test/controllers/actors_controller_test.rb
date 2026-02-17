# frozen_string_literal: true

require "test_helper"
require "securerandom"

class ActorsControllerTest < ActionDispatch::IntegrationTest
  MODERN_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

  setup do
    unique = SecureRandom.hex(8)

    @admin = User.create!(
      name: "Admin",
      email: "admin-#{unique}@example.com",
      password: "password",
      password_confirmation: "password",
      admin: true
    )

    @target = User.create!(
      name: "Target",
      email: "target-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )
  end

  def sign_in_as(user)
    post user_session_path,
         params: { user: { email: user.email, password: "password" } },
         headers: { "User-Agent" => MODERN_UA }
    assert_response :redirect
  end

  test "actor switch to user persists across refresh" do
    sign_in_as @admin

    post actor_switch_path,
         params: { actor_selection: "User:#{@target.id}" },
         headers: { "User-Agent" => MODERN_UA }

    assert_redirected_to root_path

    get root_path, headers: { "User-Agent" => MODERN_UA }

    assert_response :success
    # rubocop:disable Layout/LineLength
    assert_match(
      /<option[^>]*value="User:#{Regexp.escape(@target.id)}"[^>]*selected="selected"|<option[^>]*selected="selected"[^>]*value="User:#{Regexp.escape(@target.id)}"/, @response.body
    )
    # rubocop:enable Layout/LineLength
  end

  test "top nav actor select uses stimulus autosubmit" do
    sign_in_as @admin

    get root_path, headers: { "User-Agent" => MODERN_UA }

    assert_response :success
    assert_includes @response.body, "data-controller=\"autosubmit\""
    assert_includes @response.body, "data-action=\"change-&gt;autosubmit#submit\""
    assert_not_includes @response.body, "onchange=\"this.form.requestSubmit()\""
  end
end

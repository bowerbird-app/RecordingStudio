# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  def setup
    User.delete_all
    SystemActor.delete_all

    @admin = User.create!(name: "Admin", email: "admin@example.com", password: "password123", admin: true)
    @user = User.create!(name: "User", email: "user@example.com", password: "password123")
    @system_actor = SystemActor.create!(name: "Background task")
  end

  def test_actor_switcher_options_for_system_actor
    grouped, selected, blank = actor_switcher_options(
      current_actor: @system_actor,
      current_user: @admin,
      true_user: @admin,
      system_actors: [@system_actor],
      impersonating: false
    )

    assert_equal "SystemActor:#{@system_actor.id}", selected
    assert_equal "Signed in as #{@admin.name}", blank
    assert_equal [@user.name, "User:#{@user.id}"], (grouped["Users"].find { |pair| pair.last == "User:#{@user.id}" })
    assert_equal ["#{@system_actor.name} (System)", "SystemActor:#{@system_actor.id}"], grouped["System actors"].first
  end

  def test_actor_switcher_options_for_impersonation
    grouped, selected, _blank = actor_switcher_options(
      current_actor: @user,
      current_user: @user,
      true_user: @admin,
      system_actors: [],
      impersonating: true
    )

    assert_equal "User:#{@user.id}", selected
    assert_equal 1, grouped["Users"].size
  end

  def test_actor_label_helpers
    assert_equal "System", actor_label(nil)
    assert_equal "#{@system_actor.name} (System)", actor_label(@system_actor)
    assert_equal "#{@user.name} (User)", actor_label(@user)

    label = actor_with_impersonator_label(@user, @admin)
    assert_includes label, "impersonated by"
  end
end

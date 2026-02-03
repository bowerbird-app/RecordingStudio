# frozen_string_literal: true

require "test_helper"

class ActorsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  def setup
    @routes = Rails.application.routes
    User.delete_all
    SystemActor.delete_all

    @admin = User.create!(name: "Admin", email: "admin@example.com", password: "password123", admin: true)
    @user = User.create!(name: "User", email: "user@example.com", password: "password123")
    @system_actor = SystemActor.create!(name: "Background task")

    sign_in @admin
  end

  def test_switch_to_system_actor_sets_session
    post :switch, params: { actor_selection: "SystemActor:#{@system_actor.id}" }

    assert_equal "SystemActor", session[:actor_type]
    assert_equal @system_actor.id, session[:actor_id]
    assert_nil session[:impersonated_user_id]
  end

  def test_switch_to_user_impersonates_and_clears_system_actor
    session[:actor_type] = "SystemActor"
    session[:actor_id] = @system_actor.id

    post :switch, params: { actor_selection: "User:#{@user.id}" }

    assert_nil session[:actor_type]
    assert_nil session[:actor_id]
    assert_equal @user.id, session[:impersonated_user_id]
  end

  def test_switch_clears_all_on_blank_selection
    session[:actor_type] = "SystemActor"
    session[:actor_id] = @system_actor.id
    session[:impersonated_user_id] = @user.id

    post :switch, params: { actor_selection: "" }

    assert_nil session[:actor_type]
    assert_nil session[:actor_id]
    assert_nil session[:impersonated_user_id]
  end

  def test_update_switches_system_actor
    post :update, params: { actor_id: "SystemActor:#{@system_actor.id}" }

    assert_equal "SystemActor", session[:actor_type]
    assert_equal @system_actor.id, session[:actor_id]
  end

  def test_update_clears_system_actor_on_blank
    session[:actor_type] = "SystemActor"
    session[:actor_id] = @system_actor.id

    post :update, params: { actor_id: "" }

    assert_nil session[:actor_type]
    assert_nil session[:actor_id]
  end

  def test_update_rejects_non_system_actor
    session[:actor_type] = "SystemActor"
    session[:actor_id] = @system_actor.id

    post :update, params: { actor_id: "User:#{@user.id}" }

    assert_nil session[:actor_type]
    assert_nil session[:actor_id]
  end
end

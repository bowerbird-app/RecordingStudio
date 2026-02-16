# frozen_string_literal: true

require_relative "../test_helper"

class BasicModelsTest < ActiveSupport::TestCase
  test "workspace validates name presence" do
    workspace = Workspace.new(name: nil)

    refute workspace.valid?
    assert_includes workspace.errors[:name], "can't be blank"
  end

  test "system actor validates name presence" do
    actor = SystemActor.new(name: nil)

    refute actor.valid?
    assert_includes actor.errors[:name], "can't be blank"
  end

  test "user validates name presence" do
    user = User.new(email: "valid@example.com", password: "password123", password_confirmation: "password123", name: nil)

    refute user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end
end

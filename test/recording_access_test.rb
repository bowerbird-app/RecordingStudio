# frozen_string_literal: true

require "test_helper"

class RecordingAccessTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[Page Comment RecordingStudioAccess]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudioAccess.delete_all
    Page.delete_all
    Comment.delete_all
    Workspace.delete_all
    User.delete_all
    Team.delete_all
    SystemActor.delete_all
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_direct_grant_on_recording
    workspace = Workspace.create!(name: "Workspace")
    user = User.create!(name: "Viewer", email: "viewer@example.com", password: "password123")
    page_recording = workspace.record(Page) { |page| page.title = "Page" }

    workspace.record(RecordingStudioAccess, parent_recording: page_recording) do |access|
      access.grantee = user
      access.access_level = "view"
    end

    assert RecordingStudio::RecordingAccess.can_view?(user, page_recording)
    refute RecordingStudio::RecordingAccess.can_edit?(user, page_recording)
  end

  def test_grant_on_ancestor_applies_to_child
    workspace = Workspace.create!(name: "Workspace")
    user = User.create!(name: "Editor", email: "editor@example.com", password: "password123")
    page_recording = workspace.record(Page) { |page| page.title = "Root" }
    comment_recording = workspace.record(Comment, parent_recording: page_recording) { |comment| comment.body = "Child" }

    workspace.record(RecordingStudioAccess, parent_recording: page_recording) do |access|
      access.grantee = user
      access.access_level = "view"
    end

    assert RecordingStudio::RecordingAccess.can_view?(user, comment_recording)
  end

  def test_deny_when_no_grant
    workspace = Workspace.create!(name: "Workspace")
    user = User.create!(name: "NoAccess", email: "noaccess@example.com", password: "password123")
    page_recording = workspace.record(Page) { |page| page.title = "Page" }

    refute RecordingStudio::RecordingAccess.can_view?(user, page_recording)
  end

  def test_edit_implies_view
    workspace = Workspace.create!(name: "Workspace")
    user = User.create!(name: "Editor", email: "edit@example.com", password: "password123")
    page_recording = workspace.record(Page) { |page| page.title = "Page" }

    workspace.record(RecordingStudioAccess, parent_recording: page_recording) do |access|
      access.grantee = user
      access.access_level = "edit"
    end

    assert RecordingStudio::RecordingAccess.can_edit?(user, page_recording)
    assert RecordingStudio::RecordingAccess.can_view?(user, page_recording)
  end

  def test_cycle_safety_in_traversal
    workspace = Workspace.create!(name: "Workspace")
    user = User.create!(name: "Viewer", email: "cycle@example.com", password: "password123")
    page_recording = workspace.record(Page) { |page| page.title = "Page" }

    access_recording = workspace.record(RecordingStudioAccess, parent_recording: page_recording) do |access|
      access.grantee = user
      access.access_level = "view"
    end

    page_recording.update!(parent_recording: access_recording)

    assert RecordingStudio::RecordingAccess.can_view?(user, page_recording)
  end

  def test_polymorphic_grantees
    workspace = Workspace.create!(name: "Workspace")
    team = Team.create!(name: "Team")
    bot = SystemActor.create!(name: "Bot")
    page_recording = workspace.record(Page) { |page| page.title = "Page" }

    workspace.record(RecordingStudioAccess, parent_recording: page_recording) do |access|
      access.grantee = team
      access.access_level = "view"
    end
    workspace.record(RecordingStudioAccess, parent_recording: page_recording) do |access|
      access.grantee = bot
      access.access_level = "edit"
    end

    assert RecordingStudio::RecordingAccess.can_view?(team, page_recording)
    assert RecordingStudio::RecordingAccess.can_edit?(bot, page_recording)
  end
end

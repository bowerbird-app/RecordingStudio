# frozen_string_literal: true

require "test_helper"

class DeviceSessionConcernTest < ActiveSupport::TestCase
  RequestStub = Struct.new(:user_agent)

  class SignedCookiesStub
    attr_reader :store

    def initialize
      @store = {}
    end

    def [](key)
      store[key]
    end

    def []=(key, value)
      store[key] = value
    end
  end

  class CookiesStub
    attr_reader :signed

    def initialize
      @signed = SignedCookiesStub.new
    end
  end

  class ControllerStub
    include RecordingStudio::Concerns::DeviceSessionConcern

    attr_reader :request, :cookies

    def initialize(actor:)
      @actor = actor
      @request = RequestStub.new("Test Agent")
      @cookies = CookiesStub.new
    end

    def current_actor
      @actor
    end
  end

  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_device_sessions_flag = RecordingStudio.features.device_sessions?
    RecordingStudio.features.device_sessions = true
    RecordingStudio.configuration.recordable_types = %w[
      Workspace RecordingStudioPage
      RecordingStudio::Access RecordingStudio::AccessBoundary
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::DeviceSession.delete_all
    RecordingStudio::Recording.unscoped.delete_all
    RecordingStudio::Access.delete_all
    Workspace.delete_all
    User.delete_all

    @user = User.create!(name: "Alice", email: "alice-concern@example.com", password: "password123")
    @workspace = Workspace.create!(name: "Concern Workspace")
    @root_recording = RecordingStudio::Recording.create!(recordable: @workspace)
    grant_root_access(@root_recording, @user, :view)
  end

  def teardown
    RecordingStudio.features.device_sessions = @original_device_sessions_flag
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_current_root_recording_does_not_create_cookie_or_device_session_when_feature_disabled
    RecordingStudio.features.device_sessions = false
    controller = ControllerStub.new(actor: @user)

    root = controller.send(:current_root_recording)

    assert_equal @root_recording.id, root.id
    assert_nil controller.cookies.signed[:rs_device_id]
    assert_equal 0, RecordingStudio::DeviceSession.count
  end

  def test_current_root_recording_creates_device_session_when_feature_enabled
    controller = ControllerStub.new(actor: @user)

    root = controller.send(:current_root_recording)

    assert_equal @root_recording.id, root.id
    assert_not_nil controller.cookies.signed[:rs_device_id]
    assert_equal 1, RecordingStudio::DeviceSession.count
  end

  private

  def grant_root_access(root_recording, actor, role)
    access = RecordingStudio::Access.create!(actor: actor, role: role)
    RecordingStudio::Recording.create!(
      root_recording: root_recording,
      recordable: access,
      parent_recording: root_recording
    )
  end
end

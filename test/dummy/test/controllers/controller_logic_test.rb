# frozen_string_literal: true

require_relative "../test_helper"

class ControllerLogicTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      name: "Controller User",
      email: "controller-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @workspace = Workspace.create!(name: "Workspace #{SecureRandom.hex(3)}")
    @root = RecordingStudio::Recording.create!(recordable: @workspace)
  end

  def teardown
    Current.reset_all
  end

  test "application controller resolves actor from key" do
    user = User.create!(name: "Actor", email: "actor-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123")
    system_actor = SystemActor.create!(name: "System")
    controller = ApplicationController.new

    assert_equal user, controller.send(:actor_from_key, "User:#{user.id}")
    assert_equal system_actor, controller.send(:actor_from_key, "SystemActor:#{system_actor.id}")
    assert_nil controller.send(:actor_from_key, "Unknown:1")
    assert_nil controller.send(:actor_from_key, nil)
  end

  test "application controller require_root_access raises when not allowed" do
    controller = ApplicationController.new
    actor = @user
    root = @root
    controller.singleton_class.send(:define_method, :current_actor) { actor }

    RecordingStudio::Services::AccessCheck.stub(:root_recording_ids_for, []) do
      assert_raises(RecordingStudio::AccessDenied) do
        controller.send(:require_root_access!, root, minimum_role: :view)
      end
    end
  end

  test "application controller require_root_access passes when allowed" do
    controller = ApplicationController.new
    actor = @user
    root = @root
    controller.singleton_class.send(:define_method, :current_actor) { actor }

    RecordingStudio::Services::AccessCheck.stub(:root_recording_ids_for, [ root.id ]) do
      controller.send(:require_root_access!, root, minimum_role: :admin)
    end

    assert true
  end

  test "application controller handle_access_denied renders html" do
    controller = ApplicationController.new
    rendered = []
    format = Struct.new(:rendered) do
      def html(&block)
        block.call
      end

      def any
      end
    end.new(rendered)
    controller.singleton_class.send(:define_method, :render) { |template, **kwargs| rendered << [ template, kwargs ] }
    controller.singleton_class.send(:define_method, :respond_to) { |&block| block.call(format) }

    controller.send(:handle_access_denied)

    assert_equal [ [ "shared/no_access", { status: :forbidden } ] ], rendered
  end

  test "application controller handle_access_denied responds to any format" do
    controller = ApplicationController.new
    heads = []
    format = Struct.new(:heads) do
      def html
      end

      def any(&block)
        block.call
      end
    end.new(heads)
    controller.singleton_class.send(:define_method, :head) { |status| heads << status }
    controller.singleton_class.send(:define_method, :respond_to) { |&block| block.call(format) }

    controller.send(:handle_access_denied)

    assert_equal [ :forbidden ], heads
  end

  test "application controller current_actor uses system actor from session" do
    system_actor = SystemActor.create!(name: "Session Actor")
    controller = ApplicationController.new
    session_hash = { actor_type: "SystemActor", actor_id: system_actor.id }
    controller.singleton_class.send(:define_method, :session) { session_hash.with_indifferent_access }
    controller.singleton_class.send(:define_method, :current_user) { nil }
    controller.singleton_class.send(:define_method, :true_user) { nil }

    resolved = controller.send(:current_actor)

    assert_equal system_actor, resolved
    assert_equal system_actor, Current.actor
    assert_nil Current.impersonator
  end

  test "application controller current_actor uses impersonated user and sets impersonator" do
    true_user = User.create!(
      name: "True User",
      email: "true-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    impersonated = User.create!(
      name: "Impersonated User",
      email: "imp-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    controller = ApplicationController.new
    session_hash = { impersonated_user_id: impersonated.id }
    controller.singleton_class.send(:define_method, :session) { session_hash.with_indifferent_access }
    controller.singleton_class.send(:define_method, :current_user) { true_user }
    controller.singleton_class.send(:define_method, :true_user) { true_user }

    resolved = controller.send(:current_actor)

    assert_equal impersonated, resolved
    assert_equal impersonated, Current.actor
    assert_equal true_user, Current.impersonator
  end

  test "application controller impersonating returns true when session has impersonated user" do
    impersonated = User.create!(
      name: "Session Impersonated",
      email: "impersonating-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    controller = ApplicationController.new
    session_hash = { impersonated_user_id: impersonated.id }
    controller.singleton_class.send(:define_method, :session) { session_hash.with_indifferent_access }

    assert controller.send(:impersonating?)
  end

  test "application controller admin_user reflects true_user admin flag" do
    admin = User.create!(
      name: "Admin",
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      admin: true
    )
    non_admin = User.create!(
      name: "Non Admin",
      email: "non-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      admin: false
    )
    controller = ApplicationController.new
    controller.singleton_class.send(:define_method, :true_user) { admin }
    assert controller.send(:admin_user?)

    controller.singleton_class.send(:define_method, :true_user) { non_admin }
    refute controller.send(:admin_user?)
  end

  test "application controller require_admin redirects when not admin" do
    controller = ApplicationController.new
    redirects = []
    controller.singleton_class.send(:define_method, :admin_user?) { false }
    controller.singleton_class.send(:define_method, :root_path) { "/" }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    controller.send(:require_admin!)

    assert_equal "/", redirects.first[:args].first
    assert_equal "You are not authorized to impersonate.", redirects.first[:kwargs][:alert]
  end

  test "application controller system_actor_options returns ordered actors" do
    SystemActor.create!(name: "Zulu")
    SystemActor.create!(name: "Alpha")
    controller = ApplicationController.new

    names = controller.send(:system_actor_options).pluck(:name)

    assert_equal names.sort, names
  end

  test "application controller impersonated user lookup caches result" do
    impersonated = User.create!(
      name: "Cached",
      email: "cached-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    controller = ApplicationController.new
    session_hash = { impersonated_user_id: impersonated.id }
    controller.singleton_class.send(:define_method, :session) { session_hash.with_indifferent_access }

    first = controller.send(:impersonated_user_from_session)
    session_hash[:impersonated_user_id] = nil
    second = controller.send(:impersonated_user_from_session)

    assert_equal first, second
  end

  test "application controller system_actor_from_session returns nil for user actor type" do
    controller = ApplicationController.new
    session_hash = { actor_type: "User", actor_id: @user.id }
    controller.singleton_class.send(:define_method, :session) { session_hash.with_indifferent_access }

    assert_nil controller.send(:system_actor_from_session)
  end

  test "application controller actor_from_session delegates to system_actor_from_session" do
    controller = ApplicationController.new
    system_actor = SystemActor.create!(name: "Delegated")
    controller.singleton_class.send(:define_method, :system_actor_from_session) { system_actor }

    assert_equal system_actor, controller.send(:actor_from_session)
  end

  test "access recordings safe return_to accepts local path" do
    controller = AccessRecordingsController.new
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(return_to: "/workspaces?x=1") }
    controller.singleton_class.send(:define_method, :request) { Struct.new(:referer).new(nil) }

    assert_equal "/workspaces?x=1", controller.send(:safe_return_to)
  end

  test "access recordings safe return_to rejects external urls" do
    controller = AccessRecordingsController.new
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(return_to: "https://example.com/workspaces") }
    controller.singleton_class.send(:define_method, :request) { Struct.new(:referer).new(nil) }

    assert_equal "/workspaces", controller.send(:safe_return_to)
  end

  test "workspaces better_access_grant compares role priority" do
    controller = WorkspacesController.new

    low = Struct.new(:role, :created_at).new("view", Time.utc(2026, 1, 1))
    high = Struct.new(:role, :created_at).new("admin", Time.utc(2026, 1, 1))
    low_recording = Struct.new(:recordable).new(low)
    high_recording = Struct.new(:recordable).new(high)

    assert controller.send(:better_access_grant?, high_recording, low_recording)
    refute controller.send(:better_access_grant?, low_recording, high_recording)
  end

  test "access recordings default return path prefers parent recording path" do
    controller = AccessRecordingsController.new
    parent = RecordingStudio::Recording.create!(
      root_recording: @root,
      parent_recording: @root,
      recordable: RecordingStudioPage.create!(title: "Parent")
    )
    controller.instance_variable_set(:@parent_recording, parent)
    controller.instance_variable_set(:@root_recording, @root)
    controller.singleton_class.send(:define_method, :recording_path) { |recording| "/recordings/#{recording.id}" }

    assert_equal "/recordings/#{parent.id}", controller.send(:default_return_path)
  end

  test "access recordings default return path falls back to workspace path" do
    controller = AccessRecordingsController.new
    controller.instance_variable_set(:@parent_recording, nil)
    controller.instance_variable_set(:@root_recording, @root)
    controller.singleton_class.send(:define_method, :workspace_path) { |workspace| "/workspaces/#{workspace.id}" }

    assert_equal "/workspaces/#{@workspace.id}", controller.send(:default_return_path)
  end

  test "access recordings actor options include users and system actors" do
    system_actor = SystemActor.create!(name: "Background")
    controller = AccessRecordingsController.new

    options = controller.send(:access_actor_options)
    flattened_values = options.map(&:last)

    assert_includes flattened_values, "User:#{@user.id}"
    assert_includes flattened_values, "SystemActor:#{system_actor.id}"
  end

  test "set_access_recording raises when recordable type is not access" do
    controller = AccessRecordingsController.new
    non_access = RecordingStudio::Recording.create!(recordable: RecordingStudioPage.create!(title: "Not Access"))
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(id: non_access.id) }

    assert_raises(ActiveRecord::RecordNotFound) { controller.send(:set_access_recording) }
  end

  test "set_access_recording assigns access recording when valid" do
    controller = AccessRecordingsController.new
    access = RecordingStudio::Access.create!(actor: @user, role: :view)
    access_recording = RecordingStudio::Recording.create!(recordable: access, root_recording: @root, parent_recording: @root)
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(id: access_recording.id) }

    controller.send(:set_access_recording)

    assert_equal access_recording, controller.instance_variable_get(:@access_recording)
  end

  test "set_access_context resolves parent and root recording" do
    controller = AccessRecordingsController.new
    child = RecordingStudio::Recording.create!(
      root_recording: @root,
      parent_recording: @root,
      recordable: RecordingStudioPage.create!(title: "Child")
    )
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(parent_recording_id: child.id) }

    controller.send(:set_access_context)

    assert_equal child, controller.instance_variable_get(:@parent_recording)
    assert_equal @root, controller.instance_variable_get(:@root_recording)
  end

  test "set_access_context resolves root when parent param missing" do
    controller = AccessRecordingsController.new
    root_id = @root.id
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(root_recording_id: root_id) }

    controller.send(:set_access_context)

    assert_nil controller.instance_variable_get(:@parent_recording)
    assert_equal @root, controller.instance_variable_get(:@root_recording)
  end

  test "safe return_to returns nil for invalid uri" do
    controller = AccessRecordingsController.new
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(return_to: "%zz") }
    controller.singleton_class.send(:define_method, :request) { Struct.new(:referer).new(nil) }

    assert_nil controller.send(:safe_return_to)
  end

  test "set_return_to stores computed safe path" do
    controller = AccessRecordingsController.new
    controller.singleton_class.send(:define_method, :safe_return_to) { "/recordings/abc" }

    controller.send(:set_return_to)

    assert_equal "/recordings/abc", controller.instance_variable_get(:@return_to)
  end

  test "access_exists_for_actor checks root level access" do
    controller = AccessRecordingsController.new
    access = RecordingStudio::Access.create!(actor: @user, role: :view)
    RecordingStudio::Recording.create!(recordable: access, root_recording: @root, parent_recording: @root)
    controller.instance_variable_set(:@root_recording, @root)
    controller.instance_variable_set(:@parent_recording, nil)

    assert controller.send(:access_exists_for_actor?, @user)
  end

  test "access_exists_for_actor checks scoped parent access" do
    controller = AccessRecordingsController.new
    parent = RecordingStudio::Recording.create!(
      root_recording: @root,
      parent_recording: @root,
      recordable: RecordingStudioPage.create!(title: "Scoped Parent")
    )
    access = RecordingStudio::Access.create!(actor: @user, role: :edit)
    RecordingStudio::Recording.create!(recordable: access, root_recording: @root, parent_recording: parent)
    controller.instance_variable_set(:@root_recording, @root)
    controller.instance_variable_set(:@parent_recording, parent)

    assert controller.send(:access_exists_for_actor?, @user)
  end

  test "authorize_create_access redirects when root access is missing" do
    controller = AccessRecordingsController.new
    redirects = []
    actor = @user
    controller.instance_variable_set(:@parent_recording, nil)
    controller.instance_variable_set(:@root_recording, @root)
    controller.instance_variable_set(:@return_to, nil)
    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :default_return_path) { "/workspaces/fallback" }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    RecordingStudio::Services::AccessCheck.stub(:root_recording_ids_for, []) do
      controller.send(:authorize_create_access!)
    end

    assert_equal "/workspaces/fallback", redirects.first[:args].first
    assert_equal "You are not authorized to add access.", redirects.first[:kwargs][:alert]
  end

  test "authorize_create_access returns when root access is granted" do
    controller = AccessRecordingsController.new
    redirects = []
    actor = @user
    controller.instance_variable_set(:@parent_recording, nil)
    controller.instance_variable_set(:@root_recording, @root)
    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    RecordingStudio::Services::AccessCheck.stub(:root_recording_ids_for, [ @root.id ]) do
      controller.send(:authorize_create_access!)
    end

    assert_empty redirects
  end

  test "authorize_edit_access redirects when edit access is missing" do
    controller = AccessRecordingsController.new
    redirects = []
    actor = @user
    access = RecordingStudio::Access.create!(actor: @user, role: :view)
    access_recording = RecordingStudio::Recording.create!(recordable: access, root_recording: @root, parent_recording: @root)
    controller.instance_variable_set(:@access_recording, access_recording)
    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :safe_return_to) { nil }
    controller.singleton_class.send(:define_method, :workspace_path) { |_workspace| "/workspaces/fallback" }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    RecordingStudio::Services::AccessCheck.stub(:root_recording_ids_for, []) do
      controller.send(:authorize_edit_access!)
    end

    assert_equal "/workspaces/fallback", redirects.first[:args].first
    assert_equal "You are not authorized to edit access.", redirects.first[:kwargs][:alert]
  end

  test "workspaces root_recording_for fetches root recording" do
    controller = WorkspacesController.new

    assert_equal @root, controller.send(:root_recording_for, @workspace)
  end

  test "workspaces ensure_root_access creates root access for current actor" do
    controller = WorkspacesController.new
    actor = @user
    controller.singleton_class.send(:define_method, :current_actor) { actor }

    assert_difference("RecordingStudio::Access.count", 1) do
      controller.send(:ensure_root_access!, @workspace)
    end
  end

  test "workspaces ensure_root_access skips when current actor is nil" do
    controller = WorkspacesController.new
    controller.singleton_class.send(:define_method, :current_actor) { nil }

    assert_no_difference("RecordingStudio::Access.count") do
      controller.send(:ensure_root_access!, @workspace)
    end
  end

  test "workspaces ensure_root_access does not duplicate existing grant" do
    controller = WorkspacesController.new
    actor = @user
    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.send(:ensure_root_access!, @workspace)

    assert_no_difference("RecordingStudio::Access.count") do
      controller.send(:ensure_root_access!, @workspace)
    end
  end

  test "workspaces root_access_grants chooses strongest role per actor" do
    controller = WorkspacesController.new
    access_view = RecordingStudio::Access.create!(actor: @user, role: :view)
    access_admin = RecordingStudio::Access.create!(actor: @user, role: :admin)
    old_recording = RecordingStudio::Recording.create!(recordable: access_view, root_recording: @root, parent_recording: @root)
    new_recording = RecordingStudio::Recording.create!(recordable: access_admin, root_recording: @root, parent_recording: @root)

    grants = controller.send(:root_access_grants, @root)

    assert_includes grants, new_recording
    refute_includes grants, old_recording
  end
end

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

  test "access recordings create renders new when role is invalid" do
    controller = AccessRecordingsController.new
    now_flash = {}
    rendered = []
    user_id = @user.id

    controller.instance_variable_set(:@root_recording, @root)
    controller.instance_variable_set(:@parent_recording, nil)
    controller.instance_variable_set(:@return_to, nil)
    controller.singleton_class.send(:define_method, :params) do
      ActionController::Parameters.new(access: { role: "nope", actor_key: "User:#{user_id}" })
    end
    flash_proxy = Object.new
    flash_proxy.define_singleton_method(:now) { now_flash }
    controller.singleton_class.send(:define_method, :flash) { flash_proxy }
    controller.singleton_class.send(:define_method, :render) { |template, **kwargs| rendered << [ template, kwargs ] }

    controller.create

    assert_equal "Role is invalid.", now_flash[:alert]
    assert_equal [ :new, { status: :unprocessable_entity } ], rendered.first
  end

  test "access recordings create renders new when actor is invalid" do
    controller = AccessRecordingsController.new
    now_flash = {}
    rendered = []

    controller.instance_variable_set(:@root_recording, @root)
    controller.instance_variable_set(:@parent_recording, nil)
    controller.instance_variable_set(:@return_to, nil)
    controller.singleton_class.send(:define_method, :params) do
      ActionController::Parameters.new(access: { role: "view", actor_key: "Unknown:100" })
    end
    flash_proxy = Object.new
    flash_proxy.define_singleton_method(:now) { now_flash }
    controller.singleton_class.send(:define_method, :flash) { flash_proxy }
    controller.singleton_class.send(:define_method, :render) { |template, **kwargs| rendered << [ template, kwargs ] }

    controller.create

    assert_equal "Actor is invalid.", now_flash[:alert]
    assert_equal [ :new, { status: :unprocessable_entity } ], rendered.first
  end

  test "access recordings create rejects duplicate actor access" do
    controller = AccessRecordingsController.new
    now_flash = {}
    rendered = []
    user_id = @user.id
    existing_access = RecordingStudio::Access.create!(actor: @user, role: :view)
    RecordingStudio::Recording.create!(recordable: existing_access, root_recording: @root, parent_recording: @root)

    controller.instance_variable_set(:@root_recording, @root)
    controller.instance_variable_set(:@parent_recording, nil)
    controller.instance_variable_set(:@return_to, nil)
    controller.singleton_class.send(:define_method, :params) do
      ActionController::Parameters.new(access: { role: "edit", actor_key: "User:#{user_id}" })
    end
    flash_proxy = Object.new
    flash_proxy.define_singleton_method(:now) { now_flash }
    controller.singleton_class.send(:define_method, :flash) { flash_proxy }
    controller.singleton_class.send(:define_method, :render) { |template, **kwargs| rendered << [ template, kwargs ] }

    controller.create

    assert_equal "Actor already has access.", now_flash[:alert]
    assert_equal [ :new, { status: :unprocessable_entity } ], rendered.first
  end

  test "access recordings create records access and redirects" do
    controller = AccessRecordingsController.new
    redirects = []
    actor = @user
    target_actor = User.create!(
      name: "Target Access User",
      email: "target-access-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    controller.instance_variable_set(:@root_recording, @root)
    controller.instance_variable_set(:@parent_recording, nil)
    controller.instance_variable_set(:@return_to, "/return/here")
    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :params) do
      ActionController::Parameters.new(access: { role: "admin", actor_key: "User:#{target_actor.id}" })
    end
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    assert_difference("RecordingStudio::Access.where(actor: target_actor).count", 1) do
      controller.create
    end

    assert_equal "/return/here", redirects.first[:args].first
    assert_equal "Access added.", redirects.first[:kwargs][:notice]
  end

  test "access recordings update renders edit when role is invalid" do
    controller = AccessRecordingsController.new
    now_flash = {}
    rendered = []
    access = RecordingStudio::Access.create!(actor: @user, role: :view)
    access_recording = RecordingStudio::Recording.create!(recordable: access, root_recording: @root, parent_recording: @root)

    controller.instance_variable_set(:@access_recording, access_recording)
    controller.instance_variable_set(:@return_to, nil)
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(access: { role: "bad" }) }
    flash_proxy = Object.new
    flash_proxy.define_singleton_method(:now) { now_flash }
    controller.singleton_class.send(:define_method, :flash) { flash_proxy }
    controller.singleton_class.send(:define_method, :render) { |template, **kwargs| rendered << [ template, kwargs ] }

    controller.update

    assert_equal "Role is invalid.", now_flash[:alert]
    assert_equal [ :edit, { status: :unprocessable_entity } ], rendered.first
  end

  test "access recordings update revises access and redirects" do
    controller = AccessRecordingsController.new
    redirects = []
    actor = @user
    target_actor = User.create!(
      name: "Target Update User",
      email: "target-update-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    access = RecordingStudio::Access.create!(actor: target_actor, role: :view)
    access_recording = RecordingStudio::Recording.create!(recordable: access, root_recording: @root, parent_recording: @root)

    controller.instance_variable_set(:@access_recording, access_recording)
    controller.instance_variable_set(:@return_to, "/updated/path")
    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(access: { role: "admin" }) }
    controller.singleton_class.send(:define_method, :workspace_path) { |_workspace| "/workspace/fallback" }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    assert_difference("RecordingStudio::Access.where(actor: target_actor, role: :admin).count", 1) do
      controller.update
    end

    assert_equal "/updated/path", redirects.first[:args].first
    assert_equal "Access updated.", redirects.first[:kwargs][:notice]
  end

  test "authorize_create_access returns when parent access is granted" do
    controller = AccessRecordingsController.new
    redirects = []
    actor = @user
    parent = RecordingStudio::Recording.create!(
      root_recording: @root,
      parent_recording: @root,
      recordable: RecordingStudioPage.create!(title: "Scoped Parent Access")
    )

    controller.instance_variable_set(:@root_recording, @root)
    controller.instance_variable_set(:@parent_recording, parent)
    controller.instance_variable_set(:@return_to, nil)
    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    RecordingStudio::Services::AccessCheck.stub(:allowed?, true) do
      controller.send(:authorize_create_access!)
    end

    assert_empty redirects
  end

  test "authorize_edit_access returns when parent admin is granted" do
    controller = AccessRecordingsController.new
    redirects = []
    actor = @user
    parent = RecordingStudio::Recording.create!(
      root_recording: @root,
      parent_recording: @root,
      recordable: RecordingStudioPage.create!(title: "Edit Parent")
    )
    access = RecordingStudio::Access.create!(actor: @user, role: :view)
    scoped_access_recording = RecordingStudio::Recording.create!(
      recordable: access,
      root_recording: @root,
      parent_recording: parent
    )

    controller.instance_variable_set(:@access_recording, scoped_access_recording)
    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    RecordingStudio::Services::AccessCheck.stub(:allowed?, true) do
      controller.send(:authorize_edit_access!)
    end

    assert_empty redirects
  end

  test "workspaces index returns only accessible workspaces" do
    controller = WorkspacesController.new
    actor = @user
    hidden_workspace = Workspace.create!(name: "Hidden Workspace")
    RecordingStudio::Recording.create!(recordable: hidden_workspace)

    controller.singleton_class.send(:define_method, :current_actor) { actor }

    RecordingStudio::Services::AccessCheck.stub(:root_recording_ids_for, [ @root.id ]) do
      controller.index
    end

    workspaces = controller.instance_variable_get(:@workspaces)
    assert_includes workspaces, @workspace
    refute_includes workspaces, hidden_workspace
  end

  test "workspaces show assigns grouped recordings" do
    controller = WorkspacesController.new
    actor = @user
    workspace_id = @workspace.id
    child = RecordingStudio::Recording.create!(
      root_recording: @root,
      parent_recording: @root,
      recordable: RecordingStudioPage.create!(title: "Show Child")
    )

    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(id: workspace_id) }
    controller.singleton_class.send(:define_method, :require_root_access!) { |_root, minimum_role:| minimum_role }

    RecordingStudio::Services::AccessCheck.stub(:root_recording_ids_for, [ @root.id ]) do
      controller.show
    end

    assert_equal @workspace, controller.instance_variable_get(:@workspace)
    assert_equal @root, controller.instance_variable_get(:@root_recording)
    assert_equal true, controller.instance_variable_get(:@can_edit_access)
    grouped = controller.instance_variable_get(:@recordings_by_parent)
    assert_includes grouped[@root.id], child
  end

  test "workspaces new initializes workspace" do
    controller = WorkspacesController.new

    controller.new

    assert_instance_of Workspace, controller.instance_variable_get(:@workspace)
  end

  test "workspaces create redirects on success" do
    controller = WorkspacesController.new
    actor = @user
    redirects = []

    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :workspaces_path) { "/workspaces" }
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(workspace: { name: "Created Workspace" }) }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }

    assert_difference("Workspace.count", 1) do
      controller.create
    end

    assert_equal "/workspaces", redirects.first[:args].first
    assert_equal "Workspace created.", redirects.first[:kwargs][:notice]
  end

  test "workspaces create renders new on validation failure" do
    controller = WorkspacesController.new
    actor = @user
    now_flash = {}
    rendered = []

    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(workspace: { name: "" }) }
    flash_proxy = Object.new
    flash_proxy.define_singleton_method(:now) { now_flash }
    controller.singleton_class.send(:define_method, :flash) { flash_proxy }
    controller.singleton_class.send(:define_method, :render) { |template, **kwargs| rendered << [ template, kwargs ] }

    assert_no_difference("Workspace.count") do
      controller.create
    end

    assert_equal [ :new, { status: :unprocessable_entity } ], rendered.first
    assert_includes now_flash[:alert], "Name can't be blank"
  end

  test "workspaces destroy soft-deletes root and descendants" do
    controller = WorkspacesController.new
    redirects = []
    workspace_id = @workspace.id
    actor = @user
    child = RecordingStudio::Recording.create!(
      root_recording: @root,
      parent_recording: @root,
      recordable: RecordingStudioPage.create!(title: "Workspace child")
    )

    controller.singleton_class.send(:define_method, :current_actor) { actor }
    controller.singleton_class.send(:define_method, :params) { ActionController::Parameters.new(id: workspace_id) }
    controller.singleton_class.send(:define_method, :workspaces_path) { "/workspaces" }
    controller.singleton_class.send(:define_method, :redirect_to) { |*args, **kwargs| redirects << { args: args, kwargs: kwargs } }
    controller.send(:ensure_root_access!, @workspace)

    assert_no_difference("Workspace.count") do
      controller.destroy
    end

    root_after = RecordingStudio::Recording.unscoped.find(@root.id)
    child_after = RecordingStudio::Recording.unscoped.find(child.id)
    assert_not_nil root_after.trashed_at
    assert_not_nil child_after.trashed_at
    assert_equal "/workspaces", redirects.first[:args].first
    assert_equal "Workspace deleted.", redirects.first[:kwargs][:notice]
  end

  test "workspaces better_access_grant uses created_at as tie breaker" do
    controller = WorkspacesController.new

    older = Struct.new(:role, :created_at).new("edit", Time.utc(2026, 1, 1, 10, 0, 0))
    newer = Struct.new(:role, :created_at).new("edit", Time.utc(2026, 1, 1, 10, 0, 5))
    older_recording = Struct.new(:recordable).new(older)
    newer_recording = Struct.new(:recordable).new(newer)

    assert controller.send(:better_access_grant?, newer_recording, older_recording)
    refute controller.send(:better_access_grant?, older_recording, newer_recording)
    refute controller.send(:better_access_grant?, Struct.new(:recordable).new(nil), older_recording)
    assert controller.send(:better_access_grant?, newer_recording, Struct.new(:recordable).new(nil))
  end
end

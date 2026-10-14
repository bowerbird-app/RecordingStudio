# frozen_string_literal: true

require "test_helper"

class ApiAccessTest < Minitest::Test
  AccessGrant = Struct.new(:actor, keyword_init: true)
  Context = Struct.new(:access_grant, keyword_init: true)

  module FakeAdmin
    class Configuration
      attr_accessor :access_recording_resolver, :site_admin_recording_resolver
    end

    class << self
      def configuration
        @configuration ||= Configuration.new
      end
    end
  end

  module FakeAccessible
    class << self
      attr_accessor :last_authorized_args

      def authorized?(actor:, recording:, role:)
        @last_authorized_args = { actor: actor, recording: recording, role: role }
        actor == :allowed && recording == :admin_root && role == :view
      end
    end
  end

  def setup
    stub_const("RecordingStudioAdmin", FakeAdmin)
    stub_const("RecordingStudioAccessible", FakeAccessible)
    FakeAdmin.instance_variable_set(:@configuration, nil)
    FakeAccessible.last_authorized_args = nil
  end

  def test_standard_admin_root_uses_access_recording_resolver_only
    site_root = Object.new
    access_root = Object.new
    FakeAdmin.configuration.site_admin_recording_resolver = ->(_ctx) { site_root }
    FakeAdmin.configuration.access_recording_resolver = ->(_ctx) { access_root }

    assert_same access_root, RecordingStudio::Api::Access.admin_root_recording
  end

  def test_with_site_admin_prefers_site_admin_resolver
    site_root = Object.new
    access_root = Object.new
    FakeAdmin.configuration.site_admin_recording_resolver = ->(_ctx) { site_root }
    FakeAdmin.configuration.access_recording_resolver = ->(_ctx) { access_root }

    assert_same site_root, RecordingStudio::Api::Access::WithSiteAdmin.admin_root_recording
  end

  def test_with_site_admin_falls_back_to_access_resolver
    access_root = Object.new
    FakeAdmin.configuration.access_recording_resolver = ->(_ctx) { access_root }

    assert_same access_root, RecordingStudio::Api::Access::WithSiteAdmin.admin_root_recording
  end

  def test_with_site_admin_rescues_resolver_errors
    FakeAdmin.configuration.site_admin_recording_resolver = ->(_ctx) { raise "boom" }

    assert_nil RecordingStudio::Api::Access::WithSiteAdmin.admin_root_recording
  end

  def test_standard_does_not_rescue_resolver_errors
    FakeAdmin.configuration.access_recording_resolver = ->(_ctx) { raise "boom" }

    assert_raises(RuntimeError) { RecordingStudio::Api::Access.admin_root_recording }
  end

  def test_can_view_authorizes_against_admin_root
    FakeAdmin.configuration.access_recording_resolver = ->(_ctx) { :admin_root }
    context = Context.new(access_grant: AccessGrant.new(actor: :allowed))

    assert RecordingStudio::Api::Access.can_view?(context)
    assert_equal(
      { actor: :allowed, recording: :admin_root, role: :view },
      FakeAccessible.last_authorized_args
    )
  end

  def test_can_view_is_false_without_actor
    FakeAdmin.configuration.access_recording_resolver = ->(_ctx) { :admin_root }

    refute RecordingStudio::Api::Access.can_view?(Context.new(access_grant: nil))
  end

  def test_can_view_is_false_without_recording
    FakeAdmin.configuration.access_recording_resolver = ->(_ctx) {}

    refute RecordingStudio::Api::Access.can_view?(
      Context.new(access_grant: AccessGrant.new(actor: :allowed))
    )
  end

  def test_returns_nil_and_false_when_admin_gem_missing
    Object.send(:remove_const, :RecordingStudioAdmin) if defined?(RecordingStudioAdmin)

    assert_nil RecordingStudio::Api::Access.admin_root_recording
    refute RecordingStudio::Api::Access.can_view?(
      Context.new(access_grant: AccessGrant.new(actor: :allowed))
    )
  ensure
    stub_const("RecordingStudioAdmin", FakeAdmin)
  end

  private

  def stub_const(name, value)
    Object.send(:remove_const, name) if Object.const_defined?(name, false)
    Object.const_set(name, value)
  end
end

# frozen_string_literal: true

module RecordingStudio
  module Api
    # Shared admin-root access helpers for Recording Studio addon API modules.
    #
    # Addon gems historically copied near-identical `Api::Access` modules. Use
    # {Access} for the access-recording resolver (messages / Oauth / trashable)
    # or {Access::WithSiteAdmin} when the gem prefers
    # `site_admin_recording_resolver` with error rescue (AI / notifications /
    # presskits / terms_and_conditions).
    #
    # Soft-depends on RecordingStudioAdmin and RecordingStudioAccessible; when
    # those gems are absent the checks return false / nil like the copies.
    module Access
      module_function

      ResolverContext = Struct.new(:controller)

      # Resolve the admin root via `access_recording_resolver` only.
      #
      # @return [Object, nil]
      def admin_root_recording
        resolve_admin_root_recording(prefer_site_admin: false, rescue_errors: false)
      end

      # @param context [#access_grant, nil]
      # @return [Object, nil]
      def actor_for(context)
        context&.access_grant&.actor
      end

      # @param context [#access_grant, nil]
      # @return [Boolean]
      def can_view?(context)
        authorized_on_admin_root?(context, :view)
      end

      # @param context [#access_grant, nil]
      # @param role [Symbol]
      # @return [Boolean]
      def authorized_on_admin_root?(context, role)
        authorized?(
          actor: actor_for(context),
          recording: admin_root_recording,
          role: role
        )
      end

      # @param prefer_site_admin [Boolean]
      # @param rescue_errors [Boolean]
      # @return [Object, nil]
      def resolve_admin_root_recording(prefer_site_admin:, rescue_errors:)
        resolver = admin_root_resolver(prefer_site_admin: prefer_site_admin)
        return unless resolver

        invoke_admin_root_resolver(resolver, rescue_errors: rescue_errors)
      end

      # @param actor [Object, nil]
      # @param recording [Object, nil]
      # @param role [Symbol]
      # @return [Boolean]
      def authorized?(actor:, recording:, role:)
        return false if actor.blank? || recording.blank?
        return false unless defined?(RecordingStudioAccessible)

        RecordingStudioAccessible.authorized?(
          actor: actor,
          recording: recording,
          role: role
        )
      end

      def admin_root_resolver(prefer_site_admin:)
        return unless defined?(RecordingStudioAdmin)

        config = RecordingStudioAdmin.configuration
        if prefer_site_admin
          config.site_admin_recording_resolver || config.access_recording_resolver
        else
          config.access_recording_resolver
        end
      end
      module_function :admin_root_resolver
      private_class_method :admin_root_resolver

      def invoke_admin_root_resolver(resolver, rescue_errors:)
        return resolver.call(ResolverContext.new(nil)) unless rescue_errors

        begin
          resolver.call(ResolverContext.new(nil))
        rescue StandardError
          nil
        end
      end
      module_function :invoke_admin_root_resolver
      private_class_method :invoke_admin_root_resolver

      # Cluster that prefers `site_admin_recording_resolver` and rescues resolver errors.
      module WithSiteAdmin
        module_function

        def admin_root_recording
          Access.resolve_admin_root_recording(prefer_site_admin: true, rescue_errors: true)
        end

        def actor_for(context)
          Access.actor_for(context)
        end

        def can_view?(context)
          authorized_on_admin_root?(context, :view)
        end

        def authorized_on_admin_root?(context, role)
          Access.authorized?(
            actor: actor_for(context),
            recording: admin_root_recording,
            role: role
          )
        end
      end
    end
  end
end

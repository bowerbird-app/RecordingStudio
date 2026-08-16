# frozen_string_literal: true

module RecordingStudio
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudio

    config.to_prepare do
      RecordingStudio::RecordableDeclarations.install_active_record_macro!
      RecordingStudio::DelegatedTypeRegistrar.apply!
      RecordingStudio.apply_capabilities!
      RecordingStudio::Engine.apply_registered_extensions!
    end

    initializer "recording_studio.before_initialize", before: "recording_studio.load_config" do |_app|
      RecordingStudio::Hooks.run(:before_initialize, self)
    end

    initializer "recording_studio.load_config" do |app|
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:recording_studio)
          rescue StandardError
            nil
          end
          RecordingStudio.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError => _e
          # ignore load errors; host app can provide initializer overrides
        end
      end

      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio)
        xcfg = app.config.x.recording_studio
        if xcfg.respond_to?(:to_h)
          RecordingStudio.configuration.merge!(xcfg.to_h)
        else
          begin
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            RecordingStudio.configuration.merge!(hash) if hash&.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end

      RecordingStudio::Hooks.run(:on_configuration, RecordingStudio.configuration)
    end

    initializer "recording_studio.after_initialize", after: "recording_studio.load_config" do |_app|
      RecordingStudio::Hooks.run(:after_initialize, self)
    end

    initializer "recording_studio.apply_model_extensions" do
      ActiveSupport.on_load(:active_record) do
        RecordingStudio::RecordableDeclarations.install_active_record_macro!
      end
    end

    class << self
      def apply_registered_extensions!
        apply_model_extensions!
        apply_controller_extensions!
      end

      def apply_model_extensions! # rubocop:disable Metrics/MethodLength
        hooks = RecordingStudio.configuration.hooks
        {
          recording: RecordingStudio::Recording,
          event: RecordingStudio::Event
        }.each do |name, klass|
          hooks.model_extensions_for(name).each do |extension|
            key = [klass.name, extension.object_id]
            next if applied_extension_keys.include?(key)

            klass.class_eval(&extension)
            applied_extension_keys.add(key)
          end
        end
      end

      def apply_controller_extensions!
        return unless defined?(RecordingStudio::ApplicationController)

        hooks = RecordingStudio.configuration.hooks
        hooks.controller_extensions_for(:application).each do |extension|
          key = ["RecordingStudio::ApplicationController", extension.object_id]
          next if applied_extension_keys.include?(key)

          RecordingStudio::ApplicationController.class_eval(&extension)
          applied_extension_keys.add(key)
        end
      end

      def applied_extension_keys
        @applied_extension_keys ||= Set.new
      end
    end
  end
end

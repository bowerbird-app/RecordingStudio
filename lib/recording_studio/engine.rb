# frozen_string_literal: true

module RecordingStudio
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudio

    config.to_prepare do
      RecordingStudio::DelegatedTypeRegistrar.apply!
    end

    # Run before_initialize hooks
    initializer "recording_studio.before_initialize", before: "recording_studio.load_config" do |_app|
      RecordingStudio::Hooks.run(:before_initialize, self)
    end

    initializer "recording_studio.load_config" do |app|
      # Load config/recording_studio.yml via Rails config_for if present
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

      # Merge Rails.application.config.x.recording_studio if present
      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio)
        xcfg = app.config.x.recording_studio
        if xcfg.respond_to?(:to_h)
          RecordingStudio.configuration.merge!(xcfg.to_h)
        else
          begin
            # try converting OrderedOptions
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            RecordingStudio.configuration.merge!(hash) if hash&.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end

      # Run on_configuration hooks after config is loaded
      RecordingStudio::Hooks.run(:on_configuration, RecordingStudio.configuration)
    end

    # Run after_initialize hooks
    initializer "recording_studio.after_initialize", after: "recording_studio.load_config" do |_app|
      RecordingStudio::Hooks.run(:after_initialize, self)
    end

    # Apply model extensions when models are loaded
    initializer "recording_studio.apply_model_extensions" do
      ActiveSupport.on_load(:active_record) do
        # Model extensions are applied when the model class is first accessed
        # via the extend_model hook in configuration
      end
    end

    # Apply controller extensions
    initializer "recording_studio.apply_controller_extensions" do
      ActiveSupport.on_load(:action_controller) do
        # Controller extensions are applied when the controller class is first accessed
        # via the extend_controller hook in configuration
      end
    end
  end
end

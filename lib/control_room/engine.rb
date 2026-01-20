# frozen_string_literal: true

module ControlRoom
  class Engine < ::Rails::Engine
    isolate_namespace ControlRoom

    config.to_prepare do
      ControlRoom::DelegatedTypeRegistrar.apply!
    end

    # Run before_initialize hooks
    initializer "control_room.before_initialize", before: "control_room.load_config" do |_app|
      ControlRoom::Hooks.run(:before_initialize, self)
    end

    initializer "control_room.load_config" do |app|
      # Load config/control_room.yml via Rails config_for if present
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:control_room)
          rescue StandardError
            nil
          end
          ControlRoom.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError => _e
          # ignore load errors; host app can provide initializer overrides
        end
      end

      # Merge Rails.application.config.x.control_room if present
      if app.config.respond_to?(:x) && app.config.x.respond_to?(:control_room)
        xcfg = app.config.x.control_room
        if xcfg.respond_to?(:to_h)
          ControlRoom.configuration.merge!(xcfg.to_h)
        else
          begin
            # try converting OrderedOptions
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            ControlRoom.configuration.merge!(hash) if hash&.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end

      # Run on_configuration hooks after config is loaded
      ControlRoom::Hooks.run(:on_configuration, ControlRoom.configuration)
    end

    # Run after_initialize hooks
    initializer "control_room.after_initialize", after: "control_room.load_config" do |_app|
      ControlRoom::Hooks.run(:after_initialize, self)
    end

    # Apply model extensions when models are loaded
    initializer "control_room.apply_model_extensions" do
      ActiveSupport.on_load(:active_record) do
        # Model extensions are applied when the model class is first accessed
        # via the extend_model hook in configuration
      end
    end

    # Apply controller extensions
    initializer "control_room.apply_controller_extensions" do
      ActiveSupport.on_load(:action_controller) do
        # Controller extensions are applied when the controller class is first accessed
        # via the extend_controller hook in configuration
      end
    end
  end
end

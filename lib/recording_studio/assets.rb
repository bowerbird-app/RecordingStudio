# frozen_string_literal: true

module RecordingStudio
  module Assets
    module_function

    def register(app)
      return unless app.config.respond_to?(:assets)

      register_paths(app)
      register_precompile(app)
    end

    def register_paths(app)
      return unless app.config.assets.respond_to?(:paths)

      images_path = RecordingStudio::Engine.root.join("app/assets/images")
      return unless images_path.directory?

      path = images_path.to_s
      app.config.assets.paths << path unless app.config.assets.paths.map(&:to_s).include?(path)
    end

    def register_precompile(app)
      return unless app.config.assets.respond_to?(:precompile)

      asset = RecordingStudio::DEFAULT_BACKGROUND_IMAGE
      app.config.assets.precompile << asset unless app.config.assets.precompile.include?(asset)
    end
    private_class_method :register_paths, :register_precompile
  end
end

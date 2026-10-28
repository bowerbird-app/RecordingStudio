# frozen_string_literal: true

module RecordingStudio
  # Layout name used when a gem setting and `configuration.layout` are both nil.
  DEFAULT_LAYOUT = "recording_studio/default_layout"
  DEFAULT_BACKGROUND_IMAGE = "recording_studio/default_background.svg"

  # Resolves one layout setting and finds hard-coded `layout "recording_studio/..."` calls.
  module Layout
    HARDCODED_LAYOUT = %r{layout\s*(?:\(\s*)?["']recording_studio/}
    POSITIONAL_PARAMETER = %i[req opt rest].freeze

    class << self
      def resolve(setting, controller:)
        case setting
        when nil, false
          setting
        when String
          layout_name!(setting)
        else
          resolve_callable(setting, controller: controller)
        end
      end

      def accept(value)
        return value if value.nil? || value == false
        return layout_name!(value) if value.is_a?(String)

        require_callable!(value)
        assert_keyword_contract!(value)
        value
      end

      # Absolute paths under `root/app/controllers` that hard-code a Recording Studio layout.
      # `ignore` paths are relative to `root` or absolute.
      def hardcoded_layout_paths(root, ignore: [])
        controller_root = File.join(root.to_s, "app", "controllers")
        return [] unless File.directory?(controller_root)

        ignored = Array(ignore).map { |path| File.expand_path(path.to_s, root.to_s) }
        Dir.glob(File.join(controller_root, "**", "*.rb")).select do |path|
          next false if ignored.include?(File.expand_path(path))

          File.read(path).match?(HARDCODED_LAYOUT)
        end
      end

      private

      def resolve_callable(setting, controller:)
        require_callable!(setting)
        assert_keyword_contract!(setting)
        normalize_callable_result(setting.call(controller: controller))
      end

      def normalize_callable_result(result)
        return result if result.nil? || result == false
        return layout_name!(result) if result.is_a?(String)

        raise ArgumentError, "layout callable must return a String, nil, or false"
      end

      def require_callable!(value)
        return if value.respond_to?(:call)

        raise ArgumentError, "layout must be nil, false, a layout name, or a callable"
      end

      def layout_name!(name)
        raise ArgumentError, "layout must be a layout name" if name.strip.empty?

        name
      end

      def assert_keyword_contract!(callable)
        return if keyword_only_controller?(callable_parameters(callable))

        raise ArgumentError, "layout callable must be called with controller: as a keyword"
      end

      def callable_parameters(callable)
        return callable.parameters if callable.respond_to?(:parameters)

        callable.method(:call).parameters
      end

      def keyword_only_controller?(parameters)
        accepts_controller = parameters.any? do |kind, name|
          kind == :keyrest || (%i[keyreq key].include?(kind) && name == :controller)
        end
        positional = parameters.any? { |kind, _name| POSITIONAL_PARAMETER.include?(kind) }
        accepts_controller && !positional
      end
    end
  end
end

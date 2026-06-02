# frozen_string_literal: true

module RecordingStudio
  # rubocop:disable Metrics/ModuleLength
  module RecordableDeclarations
    Declaration = Struct.new(
      :type,
      :label,
      :plural_label,
      :root,
      :allowed_parent_types,
      :allowed_parent_types_provided,
      keyword_init: true
    ) do
      def root?
        root == true
      end
    end

    @declarations = {}

    module ModelMacro
      def recording_studio_recordable(label:, root:, plural_label: nil, **options)
        RecordingStudio::RecordableDeclarations.register(
          self,
          label: label,
          plural_label: plural_label,
          root: root,
          options: options
        )
      end
    end

    module_function

    def register(recordable_class, label:, plural_label:, root:, options:)
      allowed_parent_types_provided = options.key?(:allowed_parent_types)
      allowed_parent_types = options[:allowed_parent_types]
      validate_declaration_arguments!(
        recordable_class,
        label: label,
        plural_label: plural_label,
        root: root,
        allowed_parent_types: allowed_parent_types,
        allowed_parent_types_provided: allowed_parent_types_provided
      )

      type_name = RecordingStudio::Identity.type_name_for(recordable_class)
      declarations[type_name] = Declaration.new(
        type: type_name,
        label: normalize_label(label),
        plural_label: normalize_label(plural_label) || normalize_label(label).pluralize,
        root: root,
        allowed_parent_types: normalize_types(allowed_parent_types).freeze,
        allowed_parent_types_provided: allowed_parent_types_provided
      ).freeze
    end

    def declarations
      @declarations
    end

    def declaration_for(recordable_or_type)
      ensure_loaded!
      declarations[RecordingStudio::Identity.type_name_for(recordable_or_type)]
    end

    def declaration_defined?(recordable_or_type)
      declaration_for(recordable_or_type).present?
    end

    def declarations_for_configured_types
      ensure_loaded!
      configured_type_names.filter_map { |type| declarations[type] }
    end

    def root_recordable_types
      ensure_loaded!
      configured_type_names.select { |type| root_allowed?(type) }
    end

    def root_allowed?(recordable_or_type)
      declaration = declaration_for(recordable_or_type)
      return handle_missing_declaration(recordable_or_type, default: true) unless declaration

      declaration.root?
    end

    def allowed_parent_types_for(recordable_or_type)
      declaration = declaration_for(recordable_or_type)
      return [] unless declaration

      declaration.allowed_parent_types
    end

    def parent_allowed?(child_type:, parent_recording:)
      return false if parent_recording.nil?

      declaration = declaration_for(child_type)
      return handle_missing_declaration(child_type, default: true) unless declaration

      declaration.allowed_parent_types.include?(parent_recording.recordable_type)
    end

    def assert_root_allowed!(recordable_or_type)
      return true if root_allowed?(recordable_or_type)

      raise RecordingStudio::RootNotAllowed,
            "#{RecordingStudio::Identity.type_name_for(recordable_or_type)} cannot be recorded as a root"
    end

    def assert_parent_allowed!(child_type:, parent_recording:)
      raise RecordingStudio::InvalidParent, "parent_recording is required" if parent_recording.nil?

      return true if parent_allowed?(child_type: child_type, parent_recording: parent_recording)

      raise RecordingStudio::InvalidParent,
            "#{RecordingStudio::Identity.type_name_for(child_type)} cannot be recorded under " \
            "#{parent_recording.recordable_type}"
    end

    def validate!
      ensure_loaded!
      configured_type_names.each do |type|
        next if declaration_defined?(type)

        handle_missing_declaration(type, default: true)
      end
      validate_declared_types_registered!
      validate_allowed_parent_types_registered!
      true
    end

    def ensure_loaded!
      Array(RecordingStudio.configuration.recordable_types).each do |type|
        RecordingStudio::Identity.type_name_for(type)&.safe_constantize
      end
    end

    def install_active_record_macro!
      return unless defined?(ActiveRecord::Base)

      ActiveRecord::Base.extend(ModelMacro) unless ActiveRecord::Base.respond_to?(:recording_studio_recordable)
    end

    def configured_type_names
      Array(RecordingStudio.configuration.recordable_types).filter_map do |type|
        type_name = RecordingStudio::Identity.type_name_for(type)
        next if type_name.blank?

        type_name
      end.uniq
    end

    def registered_type_names
      configured_type_names.to_set
    end

    def validate_declared_types_registered!
      registered_types = registered_type_names
      declarations.each_key do |type|
        next if registered_types.include?(type)

        if RecordingStudio.configuration.require_recordable_declarations
          raise RecordingStudio::InvalidRecordableDeclaration,
                "#{type} declares recording_studio_recordable(...) but is not registered in config.recordable_types"
        end

        warn_unregistered_declaration(type)
      end
    end

    def validate_allowed_parent_types_registered!
      registered_types = registered_type_names
      declarations.each_value do |declaration|
        next unless registered_types.include?(declaration.type)

        invalid_types = declaration.allowed_parent_types - registered_types.to_a
        next if invalid_types.empty?

        raise RecordingStudio::InvalidRecordableDeclaration,
              "#{declaration.type} allowed_parent_types includes unregistered type(s): #{invalid_types.join(', ')}"
      end
    end

    def validate_declaration_arguments!(recordable_class, label:, plural_label:, root:, allowed_parent_types:,
                                        allowed_parent_types_provided:)
      raise_invalid!(recordable_class, "label is required") if normalize_label(label).blank?
      raise_invalid!(recordable_class, "root must be true or false") unless [true, false].include?(root)
      if plural_label && normalize_label(plural_label).blank?
        raise_invalid!(recordable_class, "plural_label must be present when provided")
      end
      if root == false && !allowed_parent_types_provided
        raise_invalid!(recordable_class, "allowed_parent_types is required when root is false")
      end

      normalize_types(allowed_parent_types) if allowed_parent_types_provided
    end

    def normalize_types(types)
      Array(types).map do |type|
        type_name = RecordingStudio::Identity.type_name_for(type)
        if type_name.blank?
          raise RecordingStudio::InvalidRecordableDeclaration,
                "allowed_parent_types cannot include blank values"
        end

        type_name
      end.uniq
    end

    def normalize_label(value)
      value.to_s.squish.presence
    end

    def handle_missing_declaration(recordable_or_type, default:)
      type_name = RecordingStudio::Identity.type_name_for(recordable_or_type)
      if RecordingStudio.configuration.require_recordable_declarations
        raise RecordingStudio::MissingRecordableDeclaration,
              "#{type_name} is registered in config.recordable_types but does not declare " \
              "recording_studio_recordable(...). Add a recording_studio_recordable(...) declaration to " \
              "#{type_name}, or set config.require_recordable_declarations = false while migrating legacy apps."
      end

      warn_missing_declaration(type_name)
      default
    end

    def warn_missing_declaration(type_name)
      message = "[RecordingStudio] #{type_name} is registered in config.recordable_types but does not declare " \
                "recording_studio_recordable(...). Legacy fallback is enabled because " \
                "config.require_recordable_declarations = false. This fallback is deprecated. Add " \
                "recording_studio_recordable(...) to #{type_name}."
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end
    end

    def warn_unregistered_declaration(type_name)
      message = "[RecordingStudio] #{type_name} declares recording_studio_recordable(...) but is not registered " \
                "in config.recordable_types."
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end
    end

    def raise_invalid!(recordable_class, message)
      type_name = RecordingStudio::Identity.type_name_for(recordable_class)
      raise RecordingStudio::InvalidRecordableDeclaration, "#{type_name}: #{message}"
    end
  end
  # rubocop:enable Metrics/ModuleLength
end

RecordingStudio::RecordableDeclarations.install_active_record_macro! if defined?(ActiveRecord::Base)

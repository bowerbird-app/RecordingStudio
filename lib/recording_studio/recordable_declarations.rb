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

    @declaration_registry = {}
    @loaded_configured_type_names = Set.new

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
      attributes = declaration_attributes(label: label, plural_label: plural_label, root: root, options: options)
      validate_declaration_arguments!(recordable_class, attributes)
      type_name = RecordingStudio::Identity.type_name_for(recordable_class)
      declaration_registry[type_name] = build_declaration(type_name, attributes).freeze
    end

    def declaration_attributes(label:, plural_label:, root:, options:)
      {
        label: label,
        plural_label: plural_label,
        root: root,
        allowed_parent_types: options[:allowed_parent_types],
        allowed_parent_types_provided: options.key?(:allowed_parent_types)
      }
    end

    def build_declaration(type_name, attributes)
      label = normalize_label(attributes.fetch(:label))
      Declaration.new(
        type: type_name,
        label: label,
        plural_label: normalize_label(attributes.fetch(:plural_label)) || label.pluralize,
        root: attributes.fetch(:root),
        allowed_parent_types: normalize_types(attributes.fetch(:allowed_parent_types)).freeze,
        allowed_parent_types_provided: attributes.fetch(:allowed_parent_types_provided)
      )
    end

    def declarations
      declaration_registry.dup.freeze
    end

    def replace_declarations!(new_declarations)
      @declaration_registry = new_declarations.dup
      @loaded_configured_type_names = Set.new
    end

    def declaration_for(recordable_or_type)
      type_name = RecordingStudio::Identity.type_name_for(recordable_or_type)
      return if type_name.blank?

      load_configured_type!(type_name)
      declaration_registry[type_name]
    end

    def declaration_defined?(recordable_or_type)
      declaration_for(recordable_or_type).present?
    end

    def declarations_for_configured_types
      ensure_loaded!
      configured_type_names.filter_map { |type| declaration_registry[type] }
    end

    def root_recordable_types
      ensure_loaded!
      configured_type_names.select { |type| root_allowed?(type) }
    end

    def root_allowed?(recordable_or_type)
      type_name = RecordingStudio::Identity.type_name_for(recordable_or_type)
      return false unless configured_recordable_type?(type_name)

      declaration = declaration_for(type_name)
      return false if declaration.nil? && capability_owned_child_recordable?(type_name)
      return handle_missing_declaration(type_name, default: true) unless declaration

      declaration.root?
    end

    def declared_parent_types_for(recordable_or_type)
      declaration = declaration_for(recordable_or_type)
      return [] unless declaration

      declaration.allowed_parent_types
    end

    def declared_allowed_parent_types_for(recordable_or_type)
      declared_parent_types_for(recordable_or_type)
    end

    def allowed_parent_types_for(recordable_or_type)
      type_name = RecordingStudio::Identity.type_name_for(recordable_or_type)
      declaration = declaration_for(type_name)
      return [] unless declaration

      declaration.allowed_parent_types + valid_capability_parent_types_for(type_name).reject do |parent_type_name|
        declaration.allowed_parent_types.include?(parent_type_name)
      end
    end

    def parent_allowed?(child_type:, parent_recording:)
      return false if parent_recording.nil?

      child_type_name = RecordingStudio::Identity.type_name_for(child_type)
      parent_type_name = RecordingStudio::Identity.type_name_for(parent_recording.recordable_type)
      return false unless configured_recordable_type?(child_type_name)
      return false unless configured_recordable_type?(parent_type_name)

      declaration = declaration_for(child_type_name)
      return false if declaration.nil? && capability_owned_child_recordable?(child_type_name)
      return handle_missing_declaration(child_type_name, default: true) unless declaration

      declaration.allowed_parent_types.include?(parent_type_name) ||
        capability_parent_allowed?(child_type_name, parent_type_name, declaration)
    end

    def assert_root_allowed!(recordable_or_type)
      return true if root_allowed?(recordable_or_type)

      raise RecordingStudio::RootNotAllowed,
            "parent_recording_id is required for #{RecordingStudio::Identity.type_name_for(recordable_or_type)}"
    end

    def assert_parent_allowed!(child_type:, parent_recording:)
      raise RecordingStudio::InvalidParent, "parent_recording is required" if parent_recording.nil?

      return true if parent_allowed?(child_type: child_type, parent_recording: parent_recording)

      raise RecordingStudio::InvalidParent,
            "#{RecordingStudio::Identity.type_name_for(child_type)} cannot be recorded under " \
            "#{parent_recording.recordable_type}"
    end

    def enforce_configuration!
      ensure_loaded!
      configured_type_names.each do |type|
        next if declaration_defined?(type)

        handle_missing_declaration(type, default: true)
      end
      validate_declared_types_registered!
      validate_allowed_parent_types_registered!
      validate_required_parent_types!
      validate_capability_parent_allowances!
    end

    def ensure_loaded!
      configured_type_names.each { |type| load_configured_type!(type) }
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

    def configured_recordable_type?(recordable_or_type)
      type_name = RecordingStudio::Identity.type_name_for(recordable_or_type)
      type_name.present? && configured_type_names.include?(type_name)
    end

    def validate_declared_types_registered!
      registered_types = registered_type_names
      declaration_registry.each_key do |type|
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
      declaration_registry.each_value do |declaration|
        next unless registered_types.include?(declaration.type)

        invalid_types = declaration.allowed_parent_types - registered_types.to_a
        next if invalid_types.empty?

        raise RecordingStudio::InvalidRecordableDeclaration,
              "#{declaration.type} allowed_parent_types includes unregistered type(s): #{invalid_types.join(', ')}"
      end
    end

    def validate_capability_parent_allowances!
      registered_types = registered_type_names
      RecordingStudio.registered_capabilities.each do |capability_name, registration|
        source = registration[:source].to_s.strip.presence
        child_types = Array(registration[:child_recordables])
        next if child_types.empty?

        if source.blank?
          raise RecordingStudio::InvalidRecordableDeclaration,
                "#{capability_name} child_recordables require a non-blank source"
        end

        child_types.each { |child_type| validate_capability_child_type!(capability_name, child_type, registered_types) }
        validate_capability_enabled_parent_types!(capability_name, registered_types)
      end
    end

    def validate_capability_child_type!(capability_name, child_type, registered_types)
      if child_type.blank?
        raise RecordingStudio::InvalidRecordableDeclaration,
              "#{capability_name} child_recordables cannot include blank values"
      end

      unless registered_types.include?(child_type)
        raise RecordingStudio::InvalidRecordableDeclaration,
              "#{capability_name} child_recordables includes unregistered type: #{child_type}"
      end

      declaration = declaration_for(child_type)
      unless declaration
        raise RecordingStudio::InvalidRecordableDeclaration,
              "#{child_type} is a capability-owned child recordable and must declare root: false"
      end

      return unless declaration.root?

      raise RecordingStudio::InvalidRecordableDeclaration,
            "#{child_type} is a capability-owned child recordable and must declare root: false"
    end

    def validate_capability_enabled_parent_types!(capability_name, registered_types)
      invalid_parent_types =
        RecordingStudio.configuration.enabled_recordable_types_for(capability_name) - registered_types.to_a
      return if invalid_parent_types.empty?

      raise RecordingStudio::InvalidRecordableDeclaration,
            "#{capability_name} is enabled for unregistered type(s): #{invalid_parent_types.join(', ')}"
    end

    def validate_declaration_arguments!(recordable_class, attributes)
      validate_label!(recordable_class, attributes.fetch(:label))
      validate_root!(recordable_class, attributes.fetch(:root))
      validate_plural_label!(recordable_class, attributes.fetch(:plural_label))

      normalize_types(attributes.fetch(:allowed_parent_types)) if attributes.fetch(:allowed_parent_types_provided)
    end

    def validate_label!(recordable_class, label)
      raise_invalid!(recordable_class, "label is required") if normalize_label(label).blank?
    end

    def validate_root!(recordable_class, root)
      raise_invalid!(recordable_class, "root must be true or false") unless [true, false].include?(root)
    end

    def validate_plural_label!(recordable_class, plural_label)
      return unless plural_label && normalize_label(plural_label).blank?

      raise_invalid!(recordable_class, "plural_label must be present when provided")
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

    def valid_capability_parent_types_for(child_type_name)
      declaration = declaration_for(child_type_name)
      return [] unless valid_capability_child_declaration?(child_type_name, declaration)

      RecordingStudio.capability_parent_types_for(child_type_name).select do |parent_type_name|
        configured_recordable_type?(parent_type_name)
      end
    end

    def capability_parent_allowed?(child_type_name, parent_type_name, declaration)
      return false unless valid_capability_child_declaration?(child_type_name, declaration)
      return false unless configured_recordable_type?(parent_type_name)

      valid_capability_parent_types_for(child_type_name).include?(parent_type_name)
    end

    def valid_capability_child_declaration?(child_type_name, declaration)
      configured_recordable_type?(child_type_name) && declaration.present? && !declaration.root?
    end

    def capability_owned_child_recordable?(type_name)
      RecordingStudio.registered_capabilities.any? do |_capability_name, registration|
        registration[:source].present? && Array(registration[:child_recordables]).include?(type_name)
      end
    end

    def validate_required_parent_types!
      configured_type_names.each do |type_name|
        declaration = declaration_for(type_name)
        next unless declaration
        next if declaration.root?
        next if declaration.allowed_parent_types_provided
        next if capability_owned_child_recordable?(type_name)

        raise RecordingStudio::InvalidRecordableDeclaration,
              "#{type_name}: allowed_parent_types is required when root is false unless a registered capability " \
              "derives parent allowances for it"
      end
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

    def declaration_registry
      @declaration_registry ||= {}
    end

    def loaded_configured_type_names
      @loaded_configured_type_names ||= Set.new
    end

    def load_configured_type!(type_name)
      return unless configured_recordable_type?(type_name)
      return if loaded_configured_type_names.include?(type_name)

      resolved_type = type_name.safe_constantize
      loaded_configured_type_names.add(type_name) if resolved_type || rails_application_initialized?
    end

    def rails_application_initialized?
      defined?(Rails) && Rails.respond_to?(:application) && Rails.application&.initialized?
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

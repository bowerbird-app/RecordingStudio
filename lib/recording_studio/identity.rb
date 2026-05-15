# frozen_string_literal: true

module RecordingStudio
  module Identity
    module_function

    def type_name_for(recordable_or_type)
      case recordable_or_type
      when nil
        nil
      when String
        recordable_or_type.presence
      when Class
        recordable_or_type.name
      else
        recordable_or_type.class.name
      end
    end

    alias recordable_type_name type_name_for

    def resolve_type(recordable_or_type)
      type_name = type_name_for(recordable_or_type)
      return if type_name.blank?

      type_name.safe_constantize
    end

    alias recordable_class_for resolve_type

    def column_names_for(recordable_or_type)
      resolve_type(recordable_or_type)&.column_names || []
    end

    def column?(recordable_or_type, column_name)
      column_names_for(recordable_or_type).include?(column_name.to_s)
    end

    def identifier_for(recordable)
      return if recordable.nil?

      return recordable.id if recordable.respond_to?(:id) && recordable.id.present?

      global_id_for(recordable)
    end

    alias recordable_identifier identifier_for

    def global_id_for(recordable)
      return if recordable.nil? || !recordable.respond_to?(:to_global_id)

      recordable.to_global_id&.to_s
    rescue URI::GID::MissingModelIdError
      nil
    end

    alias recordable_global_id global_id_for
  end
end

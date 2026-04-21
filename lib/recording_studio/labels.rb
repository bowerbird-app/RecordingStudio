# frozen_string_literal: true

module RecordingStudio
  module Labels
    EMPTY_LABEL = "—"
    COMMENT_TYPE_NAMES = %w[RecordingStudioComment RecordingStudio::Comment].freeze

    module_function

    def name_for(recordable)
      return EMPTY_LABEL unless recordable

      explicit_name_for(recordable) ||
        heuristic_name_for(recordable) ||
        explicit_type_label_for(recordable.class)
    end

    alias label_for name_for

    def type_label_for(recordable_or_type)
      return EMPTY_LABEL if recordable_or_type.blank?

      type_name = type_name_for(recordable_or_type)
      return EMPTY_LABEL if type_name.blank?

      klass = type_name.safe_constantize

      explicit_type_label_for(klass) ||
        model_type_label_for(klass, type_name) ||
        fallback_type_label_for(type_name)
    end

    def title_for(recordable)
      return EMPTY_LABEL unless recordable

      squished_value(recordable, :title) ||
        squished_value(recordable, :name) ||
        name_for(recordable)
    end

    def summary_for(recordable)
      return if recordable.nil?

      squished_value(recordable, :summary) ||
        squished_value(recordable, :body)&.truncate(160)
    end

    def explicit_name_for(recordable)
      return normalize_label(recordable.recordable_name) if recordable.respond_to?(:recordable_name)

      return unless recordable.respond_to?(:recording_studio_label)

      normalize_label(recordable.recording_studio_label)
    end
    private_class_method :explicit_name_for

    def explicit_type_label_for(recordable_class)
      if recordable_class.respond_to?(:recordable_type_label)
        return normalize_label(recordable_class.recordable_type_label)
      end

      return unless recordable_class.respond_to?(:recording_studio_type_label)

      normalize_label(recordable_class.recording_studio_type_label)
    end
    private_class_method :explicit_type_label_for

    def heuristic_name_for(recordable)
      squished_value(recordable, :title) ||
        squished_value(recordable, :name) ||
        comment_name_for(recordable) ||
        fallback_name_for(recordable)
    end
    private_class_method :heuristic_name_for

    def comment_name_for(recordable)
      return unless comment_recordable?(recordable)

      snippet = squished_value(recordable, :body)
      snippet.present? ? "Comment: #{snippet.truncate(60)}" : "Comment"
    end
    private_class_method :comment_name_for

    def fallback_name_for(recordable)
      class_name = normalize_label(recordable.class.name) || recordable.class.to_s
      identifier = recordable.respond_to?(:id) ? recordable.id : nil
      identifier.present? ? "#{class_name} ##{identifier}" : class_name
    end
    private_class_method :fallback_name_for

    def model_type_label_for(klass, type_name)
      model_label = normalize_label(klass&.model_name&.human)
      return unless model_label.present?

      return model_label unless type_name.demodulize.start_with?("RecordingStudio")

      stripped = model_label.sub(/\ARecording studio\s+/i, "").strip
      normalize_label(stripped.underscore.humanize) || model_label
    end
    private_class_method :model_type_label_for

    def fallback_type_label_for(type_name)
      demodulized = type_name.demodulize
      normalized = demodulized.sub(/\ARecordingStudio/, "")
      normalized = demodulized if normalized.blank?
      normalized.underscore.humanize
    end
    private_class_method :fallback_type_label_for

    def type_name_for(recordable_or_type)
      case recordable_or_type
      when String
        recordable_or_type
      when Class
        recordable_or_type.name
      else
        recordable_or_type.class.name
      end
    end
    private_class_method :type_name_for

    def squished_value(recordable, method_name)
      return unless recordable.respond_to?(method_name)

      normalize_label(recordable.public_send(method_name))
    end
    private_class_method :squished_value

    def normalize_label(value)
      text = value.to_s.squish
      text.presence
    end
    private_class_method :normalize_label

    def comment_recordable?(recordable)
      COMMENT_TYPE_NAMES.include?(recordable.class.name)
    end
    private_class_method :comment_recordable?
  end
end

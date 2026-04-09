# frozen_string_literal: true

require "cgi"

module RecordingStudio
  module Capabilities
    module Copyable
      Redirect = Struct.new(:action, :location, :recording, keyword_init: true)
      Result = Struct.new(:recording, :redirect, keyword_init: true)
      SENSITIVE_RECORDABLE_TYPES = %w[
        RecordingStudio::Access
        RecordingStudio::AccessBoundary
        RecordingStudio::DeviceSession
      ].freeze

      def self.to(*_legacy_parent_types, **options)
        Module.new do
          extend ActiveSupport::Concern

          included do |base|
            next unless RecordingStudio.features.copyable?

            RecordingStudio.enable_capability(:copyable, on: base.name)
            RecordingStudio.set_capability_options(:copyable, on: base.name, **options.deep_dup)
          end
        end
      end

      module RecordingMethods
        include RecordingStudio::Capability

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def copy!(actor:, impersonator: nil, metadata: {}, deep_copy: nil, redirect: nil, return_to: nil)
          self.class.transaction do
            copy_parent = lock_copy_parent!
            copy_options = resolved_copy_options(deep_copy: deep_copy, redirect: redirect)

            assert_copyable_feature_enabled!
            assert_capability!(:copyable)
            assert_copy_parent_present!(copy_parent)
            assert_recording_visible!(actor: actor, recording: self)
            assert_copy_parent_editable!(actor: actor, copy_parent: copy_parent)

            copied = duplicate_recording_tree!(
              source_recording: self,
              target_parent: copy_parent,
              actor: actor,
              impersonator: impersonator,
              metadata: metadata,
              copy_options: copy_options
            )

            Result.new(
              recording: copied,
              redirect: build_redirect(copied, redirect: copy_options[:redirect], return_to: return_to)
            )
          end
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

        def copy_to!(new_parent: nil, **kwargs)
          if new_parent.present?
            raise ArgumentError,
                  "copy_to! no longer accepts new_parent; use copy! to duplicate within the current parent"
          end

          copy!(**kwargs)
        end

        private

        def lock_copy_parent!
          ordered_ids = [id, parent_recording_id].compact.uniq.sort
          ordered_ids.each { |recording_id| self.class.lock.find(recording_id) }

          reload
          self.class.find(parent_recording_id) if parent_recording_id.present?
        end

        def resolved_copy_options(deep_copy:, redirect:)
          capability_options = RecordingStudio.capability_options(:copyable, for_type: recordable_type) || {}

          {
            deep_copy: normalize_deep_copy_options(merge_deep_copy_options(capability_options[:deep_copy], deep_copy)),
            redirect: redirect.nil? ? capability_options[:redirect] : redirect
          }
        end

        def merge_deep_copy_options(defaults, overrides)
          return defaults if overrides.nil?
          return overrides unless defaults.is_a?(Hash) && overrides.is_a?(Hash)

          defaults.deep_dup.merge(overrides.deep_dup)
        end

        def normalize_deep_copy_options(options)
          case options
          when nil, false
            { enabled: false, include: nil, exclude: [], allow_sensitive_types: false }
          when true
            { enabled: true, include: nil, exclude: [], allow_sensitive_types: false }
          when Array
            {
              enabled: true,
              include: normalize_recordable_types(options),
              exclude: [],
              allow_sensitive_types: false
            }
          when Hash
            symbolized = options.deep_symbolize_keys
            {
              enabled: symbolized.key?(:enabled) ? !!symbolized[:enabled] : true,
              include: normalize_recordable_types(symbolized[:include]),
              exclude: normalize_recordable_types(symbolized[:exclude]) || [],
              allow_sensitive_types: !!symbolized[:allow_sensitive_types]
            }
          else
            raise ArgumentError, "deep_copy must be a boolean, array, or hash"
          end
        end

        def normalize_recordable_types(types)
          Array(types).filter_map do |type|
            type.is_a?(Class) ? type.name : type.presence&.to_s
          end.presence
        end

        def duplicate_recording_tree!(source_recording:, target_parent:, actor:, impersonator:,
                                     metadata:, copy_options:)
          duplicate = duplicate_recordable(source_recording.recordable)
          duplicate.save!

          copied_recording = RecordingStudio.record!(
            action: "copied",
            recordable: duplicate,
            root_recording: root_recording || self,
            parent_recording: target_parent,
            actor: actor,
            impersonator: impersonator,
            metadata: copy_metadata_for(source_recording, metadata)
          ).recording

          copy_child_recordings!(
            source_recording: source_recording,
            copied_recording: copied_recording,
            actor: actor,
            impersonator: impersonator,
            metadata: metadata,
            copy_options: copy_options
          )

          copied_recording
        end

        def copy_child_recordings!(source_recording:, copied_recording:, actor:, impersonator:,
                                   metadata:, copy_options:)
          return unless copy_options.dig(:deep_copy, :enabled)

          source_recording.child_recordings.reorder(:created_at, :id).each do |child_recording|
            next unless copy_child_recording?(child_recording, deep_copy_options: copy_options[:deep_copy])

            assert_recording_visible!(actor: actor, recording: child_recording)
            assert_copy_parent_editable!(actor: actor, copy_parent: child_recording.parent_recording)

            duplicate_recording_tree!(
              source_recording: child_recording,
              target_parent: copied_recording,
              actor: actor,
              impersonator: impersonator,
              metadata: metadata,
              copy_options: copy_options
            )
          end
        end

        def copy_child_recording?(recording, deep_copy_options:)
          return false unless deep_copy_options[:enabled]
          return false if excluded_recordable_type?(recording.recordable_type, deep_copy_options: deep_copy_options)

          included_types = deep_copy_options[:include]
          return true if included_types.blank?

          included_types.include?(recording.recordable_type)
        end

        def excluded_recordable_type?(recordable_type, deep_copy_options:)
          excluded_types = deep_copy_options[:exclude] || []
          return true if excluded_types.include?(recordable_type)
          return false unless SENSITIVE_RECORDABLE_TYPES.include?(recordable_type)

          deep_copy_options[:allow_sensitive_types] != true &&
            !(deep_copy_options[:include] || []).include?(recordable_type)
        end

        def copy_metadata_for(source_recording, metadata)
          metadata.merge(
            source_recording_id: source_recording.id,
            source_recordable_id: source_recording.recordable_id,
            source_recordable_type: source_recording.recordable_type
          )
        end

        def assert_copy_parent_present!(copy_parent)
          raise ArgumentError, "Cannot copy a root recording" if copy_parent.nil?
        end

        def assert_recording_visible!(actor:, recording:)
          return if RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: recording, role: :view)

          raise RecordingStudio::AccessDenied, "Actor does not have view access on the source recording"
        end

        def assert_copy_parent_editable!(actor:, copy_parent:)
          return if RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: copy_parent, role: :edit)

          raise RecordingStudio::AccessDenied, "Actor does not have edit access on the copy parent"
        end

        def build_redirect(copied_recording, redirect:, return_to:)
          case redirect&.to_sym
          when :reload
            Redirect.new(action: :reload)
          when :return_to
            sanitized_return_to = sanitize_return_to(return_to)
            return unless sanitized_return_to

            Redirect.new(action: :return_to, location: sanitized_return_to)
          when :open
            Redirect.new(action: :open, recording: copied_recording)
          end
        end

        def sanitize_return_to(candidate)
          return if candidate.blank?

          uri = URI.parse(candidate)
          path = uri.path.to_s
          decoded_path = CGI.unescape(path)

          return if path.blank? || decoded_path.blank?
          return if !path.start_with?("/") || path.start_with?("//")
          return if !decoded_path.start_with?("/") || decoded_path.start_with?("//")
          return if decoded_path.split("/").any? { |segment| %w[. ..].include?(segment) }

          path += "?#{uri.query}" if uri.query.present?
          path
        rescue URI::InvalidURIError
          nil
        end

        def assert_copyable_feature_enabled!
          unless RecordingStudio.features.copyable?
            raise RecordingStudio::CapabilityDisabled, "Legacy copyable feature is disabled"
          end

          RecordingStudio.warn_legacy_feature_use!(:copyable, used_by: "RecordingStudio::Recording#copy!")
        end
      end
    end
  end
end

RecordingStudio.register_capability(
  :copyable,
  RecordingStudio::Capabilities::Copyable::RecordingMethods,
  legacy_feature_gate: :copyable
)

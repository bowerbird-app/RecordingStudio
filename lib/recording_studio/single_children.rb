# frozen_string_literal: true

require_relative "single_children/support"

module RecordingStudio
  # At most one recording of a child type directly under a parent.
  #
  # Rules live here, outside the reloader. Register from a class body or an
  # initializer. `to_prepare` runs again on every reload.
  module SingleChildren
    INDEX_NAME = "index_recording_studio_recordings_on_single_child"
    TYPE_NAME = /\A[A-Za-z_][A-Za-z0-9_:]*\z/
    DECLARATION_KEY_PREFIX = "declaration:"
    Rule = Data.define(:key, :child_type, :parents)

    class << self
      include Support

      def declare(child_type, under:, key:)
        rule_key = normalize_key(key)
        child = normalize_type_name(child_type, "child type")
        parents = normalize_parents(under)
        rule = Rule.new(key: rule_key, child_type: child, parents: parents)
        mutex.synchronize { registry[rule_key] = rule }
        rule_key
      end

      def remove(key)
        rule_key = normalize_key(key)
        mutex.synchronize { !registry.delete(rule_key).nil? }
      end

      def sync_declaration!(declaration)
        rule_key = declaration_key(declaration.type)
        parents = parents_for_declaration(declaration)
        mutex.synchronize do
          if parents
            registry[rule_key] = Rule.new(key: rule_key, child_type: declaration.type, parents: parents)
          else
            registry.delete(rule_key)
          end
        end
        rule_key
      end

      def rebuild_declarations!(declarations)
        mutex.synchronize do
          registry.delete_if { |rule_key, _rule| rule_key.start_with?(DECLARATION_KEY_PREFIX) }
          declarations.each_value do |declaration|
            parents = parents_for_declaration(declaration)
            next unless parents

            rule_key = declaration_key(declaration.type)
            registry[rule_key] = Rule.new(key: rule_key, child_type: declaration.type, parents: parents)
          end
        end
      end

      def applies?(child, under)
        child_type = RecordingStudio::Identity.type_name_for(child)
        parent_type = parent_type_name(under)
        return false if child_type.blank? || parent_type.blank?

        mutex.synchronize { rule_applies?(child_type, parent_type) }
      end

      def lock_mode(child, parent_recording)
        return RecordingStudio::Locks::SHARE_LOCK unless applies?(child, parent_recording)

        "FOR UPDATE"
      end

      def assert_available!(child, parent_recording, except: nil)
        return unless parent_recording
        return unless applies?(child, parent_recording)

        child_type = RecordingStudio::Identity.type_name_for(child)
        return unless occupied?(parent_recording, child_type, except: except)

        raise RecordingStudio::SlotTaken,
              "#{child_type} already has a recording under this #{parent_recording.recordable_type}"
      end

      def rules
        mutex.synchronize { registry.values.map(&:dup) }
      end

      def snapshot
        mutex.synchronize { registry.transform_values(&:dup) }
      end

      def restore!(rules_by_key)
        mutex.synchronize do
          @registry = rules_by_key.to_h { |rule_key, rule| [rule_key, rule.dup] }
        end
      end
    end
  end
end

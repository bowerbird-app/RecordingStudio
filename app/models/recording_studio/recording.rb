# frozen_string_literal: true

module RecordingStudio
  # rubocop:disable Metrics/ClassLength
  class Recording < ApplicationRecord
    include RecordingStudio::Capability
    include RecordingStudio::Concerns::RecordableIdentity
    include RecordingStudio::Concerns::RecordingHierarchy
    include RecordingStudio::Concerns::RecordableCounterCaches
    include RecordingStudio::Concerns::RecordableDuplication
    include RecordingStudio::Concerns::RecordingPresentation
    include RecordingStudio::Concerns::RecordingsQuery

    self.table_name = "recording_studio_recordings"

    belongs_to :root_recording, class_name: "RecordingStudio::Recording", optional: true
    belongs_to :parent_recording, class_name: "RecordingStudio::Recording", optional: true,
                                  inverse_of: :child_recordings
    has_many :child_recordings, class_name: "RecordingStudio::Recording", foreign_key: :parent_recording_id,
                                inverse_of: :parent_recording, dependent: :nullify
    has_many :events, -> { recent }, class_name: "RecordingStudio::Event", inverse_of: :recording, dependent: :destroy

    validate :parent_recording_root_consistency
    validate :parent_recording_must_not_create_cycle

    before_create :assign_root_recording_id
    after_create :set_self_root_recording_id, if: -> { parent_recording_id.nil? && root_recording_id.nil? }
    after_commit :increment_recordable_recordings_count, on: :create
    after_commit :decrement_recordable_recordings_count, on: :destroy
    after_commit :refresh_recordable_recordings_count, on: :update

    default_scope { order(updated_at: :desc) }
    scope :recent, -> { order(updated_at: :desc) }
    scope :for_root, ->(root_id) { where(root_recording_id: root_id) }
    scope :of_type, ->(klass) { where(recordable_type: klass.to_s) }

    class << self
      def lock_ids!(ids)
        normalized_ids = Array(ids).filter_map do |value|
          next if value.blank?

          value.to_s
        end.uniq.sort

        unscoped.where(id: normalized_ids).reorder(id: :asc).lock
      end
    end

    def events(actions: nil, actor: nil, actor_type: nil, actor_id: nil, from: nil, to: nil, limit: nil, offset: nil)
      apply_event_filters(
        association(:events).scope,
        actions: actions,
        actor: actor,
        actor_type: actor_type,
        actor_id: actor_id,
        from: from,
        to: to,
        limit: limit,
        offset: offset
      )
    end

    def subtree_events(include_self: true, descendant_scope: nil, actions: nil, actor: nil, actor_type: nil,
                       actor_id: nil, from: nil, to: nil, limit: nil, offset: nil)
      descendant_recordings = subtree_recordings(include_self: false, scope: descendant_scope).select(:id)
      scope = RecordingStudio::Event.where(recording_id: descendant_recordings)
      scope = scope.or(RecordingStudio::Event.where(recording_id: id)) if include_self && id.present?
      apply_event_filters(
        scope.recent,
        actions: actions,
        actor: actor,
        actor_type: actor_type,
        actor_id: actor_id,
        from: from,
        to: to,
        limit: limit,
        offset: offset
      )
    end

    def latest_event
      association(:events).scope.first
    end

    def first_event
      association(:events).scope.reorder(occurred_at: :asc, created_at: :asc).first
    end

    def event_by_idempotency_key(idempotency_key)
      return if idempotency_key.blank?

      association(:events).scope.find_by(idempotency_key: idempotency_key)
    end

    def recordables
      ([recordable] + association(:events).scope.preload(:recordable, :previous_recordable).flat_map do |event|
        [event.recordable, event.previous_recordable]
      end).compact.uniq do |snapshot|
        [snapshot.class.base_class.name, snapshot.id]
      end
    end

    def record(recordable_or_class, actor: nil, impersonator: nil, metadata: {}, parent_recording: nil)
      recordable = build_recordable_instance(recordable_or_class)
      yield(recordable) if block_given?
      recordable.save!

      root = root_recording_or_self
      resolved_parent = parent_recording || root

      RecordingStudio.record!(
        action: "created",
        recordable: recordable,
        root_recording: root,
        parent_recording: resolved_parent,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def revise(recording, actor: nil, impersonator: nil, metadata: {})
      assert_recording_belongs_to_root!(recording)

      recordable = duplicate_recordable(recording.recordable)
      yield(recordable) if block_given?
      recordable.save!

      RecordingStudio.record!(
        action: "updated",
        recordable: recordable,
        recording: recording,
        root_recording: root_recording_or_self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def log_event(recording = self, action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current,
                  idempotency_key: nil)
      assert_recording_belongs_to_root!(recording)

      recording.log_event!(
        action: action,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    def revert(recording, to_recordable:, actor: nil, impersonator: nil, metadata: {})
      assert_recording_belongs_to_root!(recording)

      RecordingStudio.record!(
        action: "reverted",
        recordable: to_recordable,
        recording: recording,
        root_recording: root_recording_or_self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def recordings_of(recordable_class)
      recordings_query.of_type(recordable_class)
    end

    def recording_for(recordable)
      recordings_for([recordable]).first
    end

    def recordings_for(recordables)
      ordered_recordables = Array(recordables).compact.select do |recordable|
        recordable.respond_to?(:id) && recordable.id.present?
      end
      return [] if ordered_recordables.empty?

      recordings_by_key = {}
      ordered_recordables.group_by { |recordable| recordable.class.name }.each do |recordable_type, typed_recordables|
        recordings = RecordingStudio::Recording.unscoped.where(
          root_recording_id: root_query_root_id,
          recordable_type: recordable_type,
          recordable_id: typed_recordables.map(&:id).uniq
        )

        recordings.each do |recording|
          key = [recording.recordable_type, recording.recordable_id]
          recordings_by_key[key] = recording
        end
      end

      ordered_recordables.filter_map do |recordable|
        recordings_by_key[[recordable.class.name, recordable.id]]
      end
    end

    def recordables_of(recordable_class, **)
      recordings_query(type: recordable_class, **).includes(:recordable).map(&:recordable)
    end

    def child_recordings_of(parent_recording, **)
      return self.class.none if parent_recording.nil?

      assert_recording_belongs_to_root!(parent_recording)
      recordings_query(include_children: true, parent_id: parent_recording.id, **)
    end

    def events_query(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil,
                     recordable_filters: nil, recordable_scope: nil, actions: nil, actor: nil,
                     actor_type: nil, actor_id: nil, impersonator: nil, impersonator_type: nil,
                     impersonator_id: nil, from: nil, to: nil, limit: nil, offset: nil)
      scope = RecordingStudio::Event.where(
        recording_id: filtered_root_recordings_query(
          include_children: include_children,
          type: type,
          id: id,
          recording_id: recording_id,
          parent_id: parent_id,
          recordable_filters: recordable_filters,
          recordable_scope: recordable_scope
        ).select(:id)
      ).recent

      apply_event_filters(
        scope,
        actions: actions,
        actor: actor,
        actor_type: actor_type,
        actor_id: actor_id,
        impersonator: impersonator,
        impersonator_type: impersonator_type,
        impersonator_id: impersonator_id,
        from: from,
        to: to,
        limit: limit,
        offset: offset
      )
    end

    def recordings_with_events(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil,
                               recordable_filters: nil, recordable_scope: nil, actions: nil, actor: nil,
                               actor_type: nil, actor_id: nil, impersonator: nil, impersonator_type: nil,
                               impersonator_id: nil, from: nil, to: nil, order: nil, limit: nil, offset: nil)
      scope = filtered_root_recordings_query(
        include_children: include_children,
        type: type,
        id: id,
        recording_id: recording_id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope
      )

      matching_events = apply_event_filters(
        RecordingStudio::Event.where(recording_id: scope.select(:id)),
        actions: actions,
        actor: actor,
        actor_type: actor_type,
        actor_id: actor_id,
        impersonator: impersonator,
        impersonator_type: impersonator_type,
        impersonator_id: impersonator_id,
        from: from,
        to: to,
        limit: nil,
        offset: nil
      )

      scope = scope.where(id: matching_events.select(:recording_id)).distinct

      safe_order = sanitize_order_for_model(order, RecordingStudio::Recording)
      scope = scope.reorder(safe_order) if safe_order.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def recordings_with_children(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil,
                                 recordable_filters: nil, recordable_scope: nil, child_type: nil, child_id: nil,
                                 child_recording_id: nil, child_recordable_filters: nil,
                                 child_recordable_scope: nil, order: nil, limit: nil, offset: nil)
      parent_scope = filtered_root_recordings_query(
        include_children: include_children,
        type: type,
        id: id,
        recording_id: recording_id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope
      )

      matching_children = filtered_root_recordings_query(
        include_children: true,
        type: child_type,
        id: child_id,
        recording_id: child_recording_id,
        parent_id: parent_scope.select(:id),
        recordable_filters: child_recordable_filters,
        recordable_scope: child_recordable_scope
      )

      scope = parent_scope.where(id: matching_children.select(:parent_recording_id)).distinct

      safe_order = sanitize_order_for_model(order, RecordingStudio::Recording)
      scope = scope.reorder(safe_order) if safe_order.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def recordings_with_descendants(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil,
                                    recordable_filters: nil, recordable_scope: nil, descendant_type: nil,
                                    descendant_id: nil, descendant_recording_id: nil,
                                    descendant_recordable_filters: nil, descendant_recordable_scope: nil,
                                    order: nil, limit: nil, offset: nil)
      parent_scope = filtered_root_recordings_query(
        include_children: include_children,
        type: type,
        id: id,
        recording_id: recording_id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope
      )

      matching_descendants = filtered_root_recordings_query(
        include_children: true,
        type: descendant_type,
        id: descendant_id,
        recording_id: descendant_recording_id,
        parent_id: nil,
        recordable_filters: descendant_recordable_filters,
        recordable_scope: descendant_recordable_scope
      )

      scope = parent_scope.where(id: descendant_ancestor_ids_for(parent_scope, matching_descendants))

      safe_order = sanitize_order_for_model(order, RecordingStudio::Recording)
      scope = scope.reorder(safe_order) if safe_order.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def recordings_without_children(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil,
                                    recordable_filters: nil, recordable_scope: nil, child_type: nil,
                                    child_id: nil, child_recording_id: nil, child_recordable_filters: nil,
                                    child_recordable_scope: nil, order: nil, limit: nil, offset: nil)
      parent_scope = filtered_root_recordings_query(
        include_children: include_children,
        type: type,
        id: id,
        recording_id: recording_id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope
      )

      matching_children = filtered_root_recordings_query(
        include_children: true,
        type: child_type,
        id: child_id,
        recording_id: child_recording_id,
        parent_id: parent_scope.select(:id),
        recordable_filters: child_recordable_filters,
        recordable_scope: child_recordable_scope
      )

      scope = parent_scope.where.not(id: matching_children.select(:parent_recording_id)).distinct

      safe_order = sanitize_order_for_model(order, RecordingStudio::Recording)
      scope = scope.reorder(safe_order) if safe_order.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def log_event!(action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current,
                   idempotency_key: nil)
      RecordingStudio.record!(
        action: action,
        recordable: recordable,
        recording: self,
        root_recording: root_recording_or_self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    private

    def apply_event_filters(
      scope,
      actions:,
      actor:,
      actor_type:,
      actor_id:,
      from:,
      to:,
      limit:,
      offset:,
      impersonator: nil,
      impersonator_type: nil,
      impersonator_id: nil
    )
      scope = scope.with_action(actions) if actions.present?
      scope = scope.by_actor(actor) if actor.present?
      scope = scope.where(actor_type: actor_type) if actor_type.present?
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.by_impersonator(impersonator) if impersonator.present?
      scope = scope.where(impersonator_type: impersonator_type) if impersonator_type.present?
      scope = scope.where(impersonator_id: impersonator_id) if impersonator_id.present?
      scope = scope.between(from, to)
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def filtered_root_recordings_query(include_children:, type:, id:, recording_id:, parent_id:, recordable_filters:,
                                       recordable_scope:)
      scope = recordings_query(
        include_children: include_children,
        type: type,
        id: id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope
      )
      scope = scope.where(id: recording_id) if recording_id.present?
      scope
    end

    def descendant_ancestor_ids_for(parent_scope, matching_descendants)
      parent_ids = parent_scope.pluck(:id).to_set
      return [] if parent_ids.empty?

      parent_links =
        RecordingStudio::Recording
        .unscoped
        .where(root_recording_id: root_query_root_id)
        .pluck(:id, :parent_recording_id)
        .to_h

      matching_descendants.pluck(:id, :parent_recording_id)
                          .each_with_object(Set.new) do |(descendant_id, parent_id), acc|
        current_parent_id = parent_id

        while current_parent_id.present?
          acc << current_parent_id if parent_ids.include?(current_parent_id)

          break if current_parent_id == descendant_id

          current_parent_id = parent_links[current_parent_id]
        end
      end.to_a
    end

    def root_query_root_id
      RecordingStudio.root_recording_id_for(root_recording_or_self)
    end

    def build_recordable_instance(recordable_or_class)
      recordable_or_class.is_a?(Class) ? recordable_or_class.new : recordable_or_class
    end

    def increment_recordable_recordings_count
      update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
    end

    def decrement_recordable_recordings_count
      update_recordable_counter(recordable_type, recordable_id, :recordings_count, -1)
    end

    def refresh_recordable_recordings_count
      return unless previous_changes.key?("recordable_type") || previous_changes.key?("recordable_id")

      previous_type = attribute_before_last_save("recordable_type")
      previous_id = attribute_before_last_save("recordable_id")

      update_recordable_counter(previous_type, previous_id, :recordings_count, -1)
      update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
    end
  end
  # rubocop:enable Metrics/ClassLength
end

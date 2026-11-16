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

    RECORDABLES_LIMIT = 50
    NEWEST_FIRST_ORDER = { created_at: :desc, id: :desc }.freeze
    CURSOR_RECORDING_ID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    belongs_to :root_recording, class_name: "RecordingStudio::Recording", optional: true
    belongs_to :parent_recording, class_name: "RecordingStudio::Recording", optional: true,
                                  inverse_of: :child_recordings
    has_many :child_recordings, class_name: "RecordingStudio::Recording", foreign_key: :parent_recording_id,
                                inverse_of: :parent_recording, dependent: :restrict_with_error
    # delete_all bypasses Event append-only guards for intentional recording purges.
    has_many :events, -> { recent }, class_name: "RecordingStudio::Event", inverse_of: :recording,
                                     dependent: :delete_all

    validate :parent_recording_root_consistency
    validate :parent_recording_must_not_create_cycle
    validate :recordable_declaration_allows_hierarchy

    before_create :assign_root_recording_id
    after_create :set_self_root_recording_id, if: -> { parent_recording_id.nil? && root_recording_id.nil? }
    after_update :sync_subtree_event_root_recording_ids, if: :saved_change_to_root_recording_id?
    after_commit :increment_recordable_recordings_count, on: :create
    after_commit :decrement_recordable_recordings_count, on: :destroy
    after_commit :refresh_recordable_recordings_count, on: :update

    scope :recent, -> { order(updated_at: :desc) }
    scope :for_root, ->(root_id) { where(root_recording_id: root_id) }
    scope :of_type, ->(klass) { where(recordable_type: klass.to_s) }
    scope :kept, -> { RecordingStudio::RecordingFilters.apply(all) }
    # Includes the recording. A root is for_root with no walk. A nested
    # recording joins the subtree walk without its depth order or page seed.
    scope :within, ->(recording) { RecordingStudio::RecordingWithin.apply(self, recording) }
    scope :newest_first, -> { order(NEWEST_FIRST_ORDER) }
    scope :older_than_cursor, lambda { |cursor|
      RecordingStudio::Recording.keyset_compared_with(self, cursor, "<")
    }
    scope :newer_than_cursor, lambda { |cursor|
      RecordingStudio::Recording.keyset_compared_with(self, cursor, ">")
    }

    def kept?
      RecordingStudio::RecordingFilters.kept?(self) { self.class.kept.where(id: id).exists? }
    end

    class << self
      def lock_ids!(ids)
        normalized_ids = Array(ids).filter_map do |value|
          next if value.blank?

          value.to_s
        end.uniq.sort

        unscoped.where(id: normalized_ids).reorder(id: :asc).lock
      end

      def cursor_for(recording)
        raise ArgumentError, "recording is required" if recording.blank?
        raise ArgumentError, "recording must be saved" if recording.id.blank? || recording.created_at.blank?

        RecordingStudio::KeysetCursor.encode(
          "created_at" => recording.created_at.iso8601(6),
          "id" => recording.id
        )
      end

      def cursor_point(cursor)
        decoded = RecordingStudio::KeysetCursor.decode(cursor)
        created_at = Time.iso8601(decoded.fetch("created_at"))
        id = decoded.fetch("id").to_s
        raise ArgumentError if created_at.nil? || !id.match?(CURSOR_RECORDING_ID)

        [created_at, id]
      rescue ArgumentError, JSON::ParserError, KeyError, TypeError
        raise ArgumentError, "cursor is invalid"
      end

      def keyset_compared_with(scope, cursor, operator)
        return scope if cursor.blank?
        raise ArgumentError, "cursor comparison is invalid" unless %w[< >].include?(operator)

        created_at, id = cursor_point(cursor)
        scope.where(
          "(recording_studio_recordings.created_at, recording_studio_recordings.id) " \
          "#{operator} (CAST(? AS timestamp), CAST(? AS uuid))",
          created_at,
          id
        )
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
                       actor_id: nil, from: nil, to: nil, limit: nil, offset: nil,
                       allow_unsafe_recordable_query: nil)
      descendant_recordings = subtree_recordings(
        include_self: false,
        scope: descendant_scope,
        allow_unsafe_recordable_query: allow_unsafe_recordable_query
      ).select(:id)
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
      ).extending(RecordingStudio::Tree::WalkGuard)
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

    def recordables(limit: nil, cursor: nil, all: false)
      assert_recordables_page!(limit: limit, cursor: cursor, all: all)
      page_limit = all ? nil : (limit || RECORDABLES_LIMIT)
      page_cursor = all ? nil : cursor
      page = distinct_recordable_snapshots(limit: page_limit, cursor: page_cursor)
      next_cursor = recordables_next_cursor(limit: page_limit, cursor: page_cursor)
      page.define_singleton_method(:next_cursor) { next_cursor }
      page
    end

    def record(recordable_or_class, actor: nil, impersonator: nil, metadata: {}, parent_recording: nil)
      recordable = build_recordable_instance(recordable_or_class)
      yield(recordable) if block_given?

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
      RecordingStudio.assert_valid_revert_target!(recording, to_recordable)

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
                     recordable_filters: nil, recordable_scope: nil, allow_unsafe_recordable_query: nil,
                     actions: nil, actor: nil, actor_type: nil, actor_id: nil, impersonator: nil,
                     impersonator_type: nil, impersonator_id: nil, from: nil, to: nil, limit: nil, cursor: nil)
      root_wide = root_wide_events_read?(
        include_children: include_children,
        type: type,
        id: id,
        recording_id: recording_id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope
      )
      scope = if root_wide
                RecordingStudio::Event.where(root_recording_id: root_query_root_id)
              else
                RecordingStudio::Event.where(
                  recording_id: filtered_root_recordings_query(
                    include_children: include_children,
                    type: type,
                    id: id,
                    recording_id: recording_id,
                    parent_id: parent_id,
                    recordable_filters: recordable_filters,
                    recordable_scope: recordable_scope,
                    allow_unsafe_recordable_query: allow_unsafe_recordable_query
                  ).select(:id)
                )
              end

      apply_event_filters(
        scope.timeline,
        actions: actions,
        actor: actor,
        actor_type: actor_type,
        actor_id: actor_id,
        impersonator: impersonator,
        impersonator_type: impersonator_type,
        impersonator_id: impersonator_id,
        from: from,
        to: to,
        limit: root_wide && limit.nil? ? RecordingStudio::Event::ROOT_TIMELINE_LIMIT : limit,
        cursor: cursor
      )
    end

    def recordings_with_events(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil,
                               recordable_filters: nil, recordable_scope: nil, allow_unsafe_recordable_query: nil,
                               actions: nil, actor: nil, actor_type: nil, actor_id: nil, impersonator: nil,
                               impersonator_type: nil, impersonator_id: nil, from: nil, to: nil, order: nil,
                               limit: nil, offset: nil)
      scope = filtered_root_recordings_query(
        include_children: include_children,
        type: type,
        id: id,
        recording_id: recording_id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope,
        allow_unsafe_recordable_query: allow_unsafe_recordable_query
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

      apply_relation_window(
        scope.where(id: matching_events.select(:recording_id)).distinct,
        order: order,
        limit: limit,
        offset: offset
      )
    end

    def recordings_with_children(**)
      recordings_matching_related_presence(negate: false, **)
    end

    def recordings_without_children(**)
      recordings_matching_related_presence(negate: true, **)
    end

    def recordings_with_descendants(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil,
                                    recordable_filters: nil, recordable_scope: nil,
                                    allow_unsafe_recordable_query: nil, descendant_type: nil,
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
        recordable_scope: recordable_scope,
        allow_unsafe_recordable_query: allow_unsafe_recordable_query
      )

      if limit.present? && ascending_id_order?(order) &&
         descendant_type.blank? && descendant_id.blank? && descendant_recording_id.blank? &&
         descendant_recordable_filters.blank? && descendant_recordable_scope.blank?
        return recordings_with_children_page(parent_scope, limit: limit, offset: offset)
      end

      matching_descendants = filtered_root_recordings_query(
        include_children: true,
        type: descendant_type,
        id: descendant_id,
        recording_id: descendant_recording_id,
        parent_id: nil,
        recordable_filters: descendant_recordable_filters,
        recordable_scope: descendant_recordable_scope,
        allow_unsafe_recordable_query: allow_unsafe_recordable_query
      )

      table = self.class.connection.quote_table_name(self.class.table_name)
      ancestor_sql = RecordingStudio::Tree.ancestor_ids_of_matches_sql(matching_descendants)
      apply_relation_window(
        parent_scope.where("#{table}.id IN (#{ancestor_sql})"),
        order: order,
        limit: limit,
        offset: offset
      ).extending(RecordingStudio::Tree::WalkGuard)
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

    def assert_recordables_page!(limit:, cursor:, all:)
      return unless all

      raise ArgumentError, "limit is not used when all: true" unless limit.nil?
      raise ArgumentError, "cursor is not used when all: true" if cursor.present?
    end

    def recordable_event_window(limit:, cursor:)
      scope = association(:events).scope.reorder(occurred_at: :asc, created_at: :asc, id: :asc)
      scope = scope.newer_than_cursor(cursor) if cursor.present?
      scope = scope.limit(limit) if limit
      scope
    end

    def distinct_recordable_snapshots(limit:, cursor:)
      rows = first_seen_snapshot_rows(limit: limit, cursor: cursor)
      snapshots = snapshots_for(rows)
      snapshots << recordable if rows.any? || cursor.blank?
      snapshots.compact.uniq { |snapshot| [snapshot.class.base_class.name, snapshot.id] }
    end

    def first_seen_snapshot_rows(limit:, cursor:)
      window = recordable_event_window(limit: limit, cursor: cursor).select(
        "recording_studio_events.previous_recordable_type",
        "recording_studio_events.previous_recordable_id",
        "recording_studio_events.recordable_type",
        "recording_studio_events.recordable_id",
        "recording_studio_events.occurred_at",
        "recording_studio_events.created_at",
        "recording_studio_events.id"
      )
      sql = <<~SQL.squish
        WITH numbered AS (
          SELECT previous_recordable_type,
                 previous_recordable_id,
                 recordable_type,
                 recordable_id,
                 ROW_NUMBER() OVER (
                   ORDER BY occurred_at ASC, created_at ASC, id ASC
                 ) AS event_index
          FROM (#{window.to_sql}) AS windowed
        ),
        steps AS (
          SELECT previous_recordable_type AS recordable_type,
                 previous_recordable_id AS recordable_id,
                 event_index * 2 AS position
          FROM numbered
          WHERE previous_recordable_id IS NOT NULL
          UNION ALL
          SELECT recordable_type,
                 recordable_id,
                 event_index * 2 + 1 AS position
          FROM numbered
        ),
        first_seen AS (
          SELECT DISTINCT ON (recordable_type, recordable_id)
                 recordable_type,
                 recordable_id,
                 position
          FROM steps
          ORDER BY recordable_type, recordable_id, position
        )
        SELECT recordable_type, recordable_id
        FROM first_seen
        ORDER BY position
      SQL
      self.class.connection.select_all(sql).to_a
    end

    def snapshots_for(rows)
      found = {}
      rows.group_by { |row| row.fetch("recordable_type") }.each do |type, typed_rows|
        ids = typed_rows.map { |row| row.fetch("recordable_id") }
        type.constantize.where(id: ids).each do |snapshot|
          found[[type, snapshot.id.to_s]] = snapshot
        end
      end
      rows.filter_map { |row| found[[row.fetch("recordable_type"), row.fetch("recordable_id").to_s]] }
    end

    def recordables_next_cursor(limit:, cursor:)
      return if limit.nil?

      events = recordable_event_window(limit: limit, cursor: cursor).select(:id, :occurred_at, :created_at).to_a
      return if events.size != limit || events.last.nil?

      RecordingStudio::Event.cursor_for(events.last)
    end

    def recordings_with_children_page(parent_scope, limit:, offset:)
      offset = offset.to_i
      needed = limit.to_i + offset
      ids = RecordingStudio::Tree.child_owner_ids(
        root_recording_id: root_query_root_id,
        parent_scope: parent_scope,
        needed: needed
      )
      parent_scope.where(id: ids.drop(offset)).reorder(id: :asc).limit(limit.to_i)
    end

    def ascending_id_order?(order)
      case order
      when nil, ""
        true
      when Hash
        order.size == 1 && order.keys.first.to_s == "id" && order.values.first.to_s.casecmp("desc") != 0
      when String, Symbol
        order.to_s.strip.match?(/\A"?id"?(\s+asc)?\z/i)
      else
        false
      end
    end

    def recordings_matching_related_presence(include_children: true, type: nil, id: nil,
                                             recording_id: nil, parent_id: nil, recordable_filters: nil,
                                             recordable_scope: nil, allow_unsafe_recordable_query: nil,
                                             child_type: nil, child_id: nil, child_recording_id: nil,
                                             child_recordable_filters: nil, child_recordable_scope: nil,
                                             order: nil, limit: nil, offset: nil, negate: false)
      parent_scope = filtered_root_recordings_query(
        include_children: include_children,
        type: type,
        id: id,
        recording_id: recording_id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope,
        allow_unsafe_recordable_query: allow_unsafe_recordable_query
      )

      matching_related = filtered_root_recordings_query(
        include_children: true,
        type: child_type,
        id: child_id,
        recording_id: child_recording_id,
        parent_id: parent_scope.select(:id),
        recordable_filters: child_recordable_filters,
        recordable_scope: child_recordable_scope,
        allow_unsafe_recordable_query: allow_unsafe_recordable_query
      )

      related_ids = matching_related.select(:parent_recording_id)
      scope = if negate
                parent_scope.where.not(id: related_ids)
              else
                parent_scope.where(id: related_ids)
              end.distinct

      apply_relation_window(scope, order: order, limit: limit, offset: offset)
    end

    def apply_event_filters(
      scope,
      actions:,
      actor:,
      actor_type:,
      actor_id:,
      from:,
      to:,
      limit:,
      offset: nil,
      cursor: nil,
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
      scope = scope.older_than_cursor(cursor) if cursor.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def root_wide_events_read?(include_children:, type:, id:, recording_id:, parent_id:, recordable_filters:,
                               recordable_scope:)
      include_children != false &&
        [type, id, recording_id, parent_id, recordable_filters, recordable_scope].all?(&:blank?)
    end

    def filtered_root_recordings_query(include_children:, type:, id:, recording_id:, parent_id:, recordable_filters:,
                                       recordable_scope:, allow_unsafe_recordable_query: nil)
      scope = recordings_query(
        include_children: include_children,
        type: type,
        id: id,
        parent_id: parent_id,
        recordable_filters: recordable_filters,
        recordable_scope: recordable_scope,
        allow_unsafe_recordable_query: allow_unsafe_recordable_query
      )
      scope = scope.where(id: recording_id) if recording_id.present?
      scope
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

    def recordable_declaration_allows_hierarchy
      return if recordable_type.blank?

      if parent_recording_id.present?
        validate_parent_allowed
      else
        validate_parentless_allowed
      end
    end

    def validate_parent_allowed
      RecordingStudio.assert_parent_allowed!(child_type: recordable_type, parent_recording: resolved_parent_recording)
    rescue RecordingStudio::InvalidParent, RecordingStudio::MissingRecordableDeclaration => e
      errors.add(:parent_recording, e.message)
    end

    def validate_root_allowed
      RecordingStudio.assert_root_allowed!(recordable_type)
    rescue RecordingStudio::RootNotAllowed, RecordingStudio::MissingRecordableDeclaration => e
      errors.add(:recordable_type, e.message)
    end

    def validate_parentless_allowed
      if parentless_child_under_existing_root?
        errors.add(:parent_recording_id, "cannot be blank when root_recording_id points to an existing root")
        return
      end

      return validate_root_allowed if RecordingStudio.root_allowed?(recordable_type)

      errors.add(
        :parent_recording_id,
        "is required for #{recordable_type}"
      )
    rescue RecordingStudio::MissingRecordableDeclaration => e
      errors.add(:recordable_type, e.message)
    end

    def resolved_parent_recording
      self.class.unscoped.find_by(id: parent_recording_id)
    end

    def parentless_child_under_existing_root?
      root_recording_id.present? && root_recording_id != id
    end
  end
  # rubocop:enable Metrics/ClassLength
end

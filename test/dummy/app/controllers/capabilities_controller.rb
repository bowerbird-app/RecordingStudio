class CapabilitiesController < ApplicationController
  CAPABILITY_CATALOG = [
    {
      title: "Inspect Registered Capabilities",
      subtitle: "RecordingStudio.registered_capabilities",
      code: <<~'RUBY'
        registration = RecordingStudio.registered_capabilities.fetch(:reviewable)

        # => {
        #      source: "recording_studio_reviewable",
        #      child_recordables: ["Approval"]
        #    }
        registration.fetch(:child_recordables)
      RUBY
    },
    {
      title: "Register Capability Methods and Child Metadata",
      subtitle: "RecordingStudio.register_capability",
      code: <<~'RUBY'
        module Capabilities
          module Reviewable
            module RecordingMethods
              def review_events
                child_recordings.of_type("Approval")
              end
            end
          end
        end

        RecordingStudio.register_capability(
          :reviewable,
          recording_methods: Capabilities::Reviewable::RecordingMethods,
          source: "recording_studio_reviewable",
          child_recordables: ["Approval"]
        )
      RUBY
    },
    {
      title: "Apply Registered Capabilities",
      subtitle: "RecordingStudio.apply_capabilities!",
      code: <<~'RUBY'
        Rails.application.config.to_prepare do
          # Useful when addon constants are reloaded in development.
          RecordingStudio.apply_capabilities!
        end
      RUBY
    },
    {
      title: "Enable a Capability for a Recordable",
      subtitle: "RecordingStudio.enable_capability",
      code: <<~'RUBY'
        class Page < ApplicationRecord
          include Module.new {
            def self.included(base)
              RecordingStudio.enable_capability(:reviewable, on: base.name)
            end
          }
        end
      RUBY
    },
    {
      title: "Set Capability Options",
      subtitle: "RecordingStudio.set_capability_options",
      code: <<~'RUBY'
        RecordingStudio.set_capability_options(
          :reviewable,
          on: "Page",
          approval_class: "Approval"
        )
      RUBY
    },
    {
      title: "List Child Recordables Declared by a Capability",
      subtitle: "RecordingStudio.capability_child_recordables_for",
      code: <<~'RUBY'
        child_types = RecordingStudio.capability_child_recordables_for(:reviewable)

        # => ["Approval"]
        child_types
      RUBY
    },
    {
      title: "List Child Recordables Enabled for a Parent Type",
      subtitle: "RecordingStudio.child_recordable_types_for",
      code: <<~'RUBY'
        child_types = RecordingStudio.child_recordable_types_for("Page")

        # => ["Approval"]
        child_types
      RUBY
    },
    {
      title: "List Capability-Derived Parent Types",
      subtitle: "RecordingStudio.capability_allowed_parent_types_for",
      code: <<~'RUBY'
        parent_types = RecordingStudio.capability_allowed_parent_types_for("Approval")

        # => ["Page"]
        parent_types
      RUBY
    },
    {
      title: "Inspect Parent Allowances by Source",
      subtitle: "RecordingStudio.recordable_parent_allowances_for",
      code: <<~'RUBY'
        allowances = RecordingStudio.recordable_parent_allowances_for("Approval")

        # => { "recording_studio_reviewable" => ["Page"] }
        allowances.fetch("recording_studio_reviewable")
      RUBY
    },
    {
      title: "Explain Which Capability Allows a Parent/Child Pair",
      subtitle: "RecordingStudio.parent_capabilities_for",
      code: <<~'RUBY'
        capability_names = RecordingStudio.parent_capabilities_for(
          child_type: "Approval",
          parent_type: "Page"
        )

        # => [:reviewable]
        capability_names
      RUBY
    },
    {
      title: "Check Capability Availability by Type",
      subtitle: "RecordingStudio.capability_enabled?",
      code: <<~'RUBY'
        if RecordingStudio.capability_enabled?(:reviewable, for: "Page")
          # Render addon-specific UI or call capability behavior.
        end
      RUBY
    },
    {
      title: "List Enabled Capabilities for a Type",
      subtitle: "RecordingStudio.capabilities_for",
      code: <<~'RUBY'
        capability_names = RecordingStudio.capabilities_for("Page")

        # => [:reviewable]
        capability_names
      RUBY
    },
    {
      title: "Read Capability Options",
      subtitle: "RecordingStudio.capability_options",
      code: <<~'RUBY'
        options = RecordingStudio.capability_options(:reviewable, for: "Page")

        # => { approval_class: "Approval" }
        options.fetch(:approval_class)
      RUBY
    },
    {
      title: "Check Capability Availability",
      subtitle: "recording.capability_enabled?",
      code: <<~'RUBY'
        if page_recording.capability_enabled?(:reviewable)
          page_recording.capability_options(:reviewable)
        end
      RUBY
    },
    {
      title: "Read Recording Capability Options",
      subtitle: "recording.capability_options",
      code: <<~'RUBY'
        options = page_recording.capability_options(:reviewable)

        # => { approval_class: "Approval" }
        options.fetch(:approval_class)
      RUBY
    },
    {
      title: "Inspect Enabled Capabilities",
      subtitle: "recording.capabilities",
      code: <<~'RUBY'
        capability_names = page_recording.capabilities
      RUBY
    },
    {
      title: "Assert a Capability Before Use",
      subtitle: "recording.assert_capability!",
      code: <<~'RUBY'
        page_recording.assert_capability!(:reviewable)
        page_recording.capability_options(:reviewable)
      RUBY
    }
  ].freeze

  CAPABILITY_RESPONSE_DETAILS = {
    "RecordingStudio.registered_capabilities" => {
      returns_kind: "Hash",
      returns: "Hash<Symbol, Hash>",
      items: "Capability registration metadata",
      notes: "Useful for inspecting registered recording methods plus source and child-recordable metadata.",
      example_response: <<~'TEXT'
        {
          reviewable: {
            source: "recording_studio_reviewable",
            child_recordables: ["Approval"]
          }
        }
      TEXT
    },
    "RecordingStudio.register_capability" => {
      returns_kind: "Side effect",
      returns: "No stable return contract; registers capability metadata and may apply recording methods to RecordingStudio::Recording.",
      notes: "Use this for capability setup. source: is required whenever child_recordables: are present.",
      example_response: <<~'TEXT'
        RecordingStudio.capability_child_recordables_for(:reviewable)
        # => ["Approval"]
      TEXT
    },
    "RecordingStudio.apply_capabilities!" => {
      returns_kind: "Side effect",
      returns: "No stable return contract; reapplies registered capability modules to RecordingStudio::Recording.",
      notes: "Primarily useful during boot and code reloading.",
      example_response: <<~'TEXT'
        RecordingStudio::Recording.included_modules.include?(Capabilities::Reviewable::RecordingMethods)
        # => true
      TEXT
    },
    "RecordingStudio.enable_capability" => {
      returns_kind: "Side effect",
      returns: "No stable return contract; marks a recordable type as capability-enabled.",
      notes: "Updates RecordingStudio configuration for the target recordable type.",
      example_response: <<~'TEXT'
        RecordingStudio.capabilities_for("Page")
        # => [:reviewable]
      TEXT
    },
    "RecordingStudio.set_capability_options" => {
      returns_kind: "Side effect",
      returns: "No stable return contract; stores configuration for the capability and recordable type.",
      notes: "Use this to configure capability behavior, not to read it back.",
      example_response: <<~'TEXT'
        RecordingStudio.capability_options(:reviewable, for: "Page")
        # => { approval_class: "Approval" }
      TEXT
    },
    "RecordingStudio.capability_child_recordables_for" => {
      returns_kind: "Array",
      returns: "Array<String>",
      items: "Child recordable type name",
      notes: "Lists child recordables declared on a capability registration.",
      example_response: <<~'TEXT'
        ["Approval"]
      TEXT
    },
    "RecordingStudio.child_recordable_types_for" => {
      returns_kind: "Array",
      returns: "Array<String>",
      items: "Child recordable type name",
      notes: "Lists capability-owned child types enabled for the given parent type.",
      example_response: <<~'TEXT'
        ["Approval"]
      TEXT
    },
    "RecordingStudio.capability_allowed_parent_types_for" => {
      returns_kind: "Array",
      returns: "Array<String>",
      items: "Parent recordable type name",
      notes: "Lists parent types granted by capability registrations and enablement.",
      example_response: <<~'TEXT'
        ["Page"]
      TEXT
    },
    "RecordingStudio.recordable_parent_allowances_for" => {
      returns_kind: "Hash",
      returns: "Hash<String, Array<String>>",
      items: "Source name => parent type names",
      notes: "Lists capability-derived parent allowances grouped by source/provenance.",
      example_response: <<~'TEXT'
        { "recording_studio_reviewable" => ["Page"] }
      TEXT
    },
    "RecordingStudio.parent_capabilities_for" => {
      returns_kind: "Array",
      returns: "Array<Symbol>",
      items: "Capability symbol",
      notes: "Explains which enabled capabilities allow a given parent/child relationship.",
      example_response: <<~'TEXT'
        [:reviewable]
      TEXT
    },
    "RecordingStudio.capability_enabled?" => {
      returns_kind: "Boolean",
      returns: "true or false",
      notes: "Checks whether the capability is enabled for the given recordable type.",
      example_response: <<~'TEXT'
        true
      TEXT
    },
    "RecordingStudio.capabilities_for" => {
      returns_kind: "Array",
      returns: "Array<Symbol>",
      items: "Capability symbol",
      notes: "Returns enabled capability names for the target recordable type.",
      example_response: <<~'TEXT'
        [:reviewable]
      TEXT
    },
    "RecordingStudio.capability_options" => {
      returns_kind: "Hash",
      returns: "Hash or nil",
      notes: "Returns the configured option hash for the capability and type when present.",
      example_response: <<~'TEXT'
        { approval_class: "Approval" }
      TEXT
    },
    "recording.capability_enabled?" => {
      returns_kind: "Boolean",
      returns: "true or false",
      notes: "Checks whether the current recording's recordable type has the capability enabled.",
      example_response: <<~'TEXT'
        true
      TEXT
    },
    "recording.capability_options" => {
      returns_kind: "Hash",
      returns: "Hash or nil",
      notes: "Returns the configured capability options for the current recording's recordable type.",
      example_response: <<~'TEXT'
        { approval_class: "Approval" }
      TEXT
    },
    "recording.capabilities" => {
      returns_kind: "Array",
      returns: "Array<Symbol>",
      items: "Capability symbol",
      notes: "Lists enabled capability names for the current recording's recordable type.",
      example_response: <<~'TEXT'
        [:reviewable]
      TEXT
    },
    "recording.assert_capability!" => {
      returns_kind: "Guard",
      returns: "nil on success, or raises RecordingStudio::CapabilityDisabled",
      notes: "Use when capability access must fail fast instead of branching on a boolean.",
      example_response: <<~'TEXT'
        nil
      TEXT
    }
  }.freeze

  def index
    @method_catalog = CAPABILITY_CATALOG.map do |entry|
      details = CAPABILITY_RESPONSE_DETAILS.fetch(entry.fetch(:subtitle))
      entry.merge(details).merge(code: append_response_details(entry.fetch(:code), details))
    end
  end

  private

  def append_response_details(code, details)
    [ code.chomp, response_details_comment_block(details) ].join("\n\n")
  end

  def response_details_comment_block(details)
    lines = []
    lines << "# Response"
    lines << "# Returns: #{details.fetch(:returns)}"
    lines << "# Type: #{details.fetch(:returns_kind)}" if details[:returns_kind].present?
    lines << "# Items: #{details.fetch(:items)}" if details[:items].present?
    lines << "# Yields: #{details.fetch(:yields)}" if details[:yields].present?
    lines << "# Notes: #{details.fetch(:notes)}" if details[:notes].present?
    if details[:example_response].present?
      lines << "# Example response:"
      details[:example_response].chomp.split("\n").each do |line|
        lines << "#   #{line}"
      end
    end
    lines.join("\n")
  end
end

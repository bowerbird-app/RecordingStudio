class CapabilitiesController < ApplicationController
  CAPABILITY_CATALOG = [
    {
      title: "Inspect Registered Capabilities",
      subtitle: "RecordingStudio.registered_capabilities",
      code: <<~'RUBY'
        RecordingStudio.registered_capabilities.keys
        # => [:reviewable]
      RUBY
    },
    {
      title: "Register Capability Methods",
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

        # This mixes the API into RecordingStudio::Recording.
        RecordingStudio.register_capability(:reviewable, Capabilities::Reviewable::RecordingMethods)
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
      notes: "Useful for inspecting which recording-level capability modules have been registered.",
      example_response: <<~'TEXT'
        { reviewable: { mod: Capabilities::Reviewable::RecordingMethods } }
      TEXT
    },
    "RecordingStudio.register_capability" => {
      returns_kind: "Side effect",
      returns: "No stable return contract; registers the capability and may apply it to RecordingStudio::Recording.",
      notes: "Use this for capability setup, not as a query API.",
      example_response: <<~'TEXT'
        RecordingStudio.registered_capabilities.keys
        # => [:reviewable]
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

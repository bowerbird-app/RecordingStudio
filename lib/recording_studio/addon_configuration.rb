# frozen_string_literal: true

require_relative "hooks"

module RecordingStudio
  # Thin configuration base for Recording Studio addon gems.
  #
  # Addon gems historically copied the same `hooks` reader, `Hooks.new` default,
  # and setter-dispatch `merge!`. Inherit this class and declare gem-specific
  # attributes in the subclass.
  #
  # @example
  #   class Configuration < RecordingStudio::AddonConfiguration
  #     attr_accessor :timeout
  #
  #     def initialize
  #       super
  #       @timeout = 5
  #     end
  #
  #     def to_h
  #       { timeout: timeout, hooks_registered: hooks_registered }
  #     end
  #   end
  class AddonConfiguration
    attr_reader :hooks

    def initialize(hooks: nil)
      @hooks = hooks || Hooks.new
    end

    # Counts of registered hooks by event name (for `to_h` summaries).
    #
    # @return [Hash{Symbol => Integer}]
    def hooks_registered
      hooks.registered_counts
    end

    # Apply compatible keys from a hash via public setters.
    #
    # @param hash [#each] hash-like object
    # @return [void]
    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |key, value|
        setter = "#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
    end
  end
end

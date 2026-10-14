# frozen_string_literal: true

require "erb"
require "yaml"

module RecordingStudio
  # Locale lookups for gem-shipped `recording_studio.*` keys.
  #
  # Fallback order for gem keys missing in the active locale:
  # 1. loaded `:en` (host English overrides included)
  # 2. caller's `default:`
  # 3. merged gem-shipped English table (base `config/locales/en.yml` plus
  #    paths registered via {register_shipped_english})
  #
  # Non-gem keys, present locale values, Arrays, and lazy keys pass through
  # like `I18n.t`. `_html` keys escape interpolation args then mark html_safe,
  # matching view `t`. A missing `_html` key with a non-interpolating caller
  # `default:` stays unsafe like view `t`. An interpolating caller `default:`
  # is stricter: args are escaped and the result is marked html_safe.
  #
  # Partial pluralization data in a non-English locale still raises
  # `I18n::InvalidPluralizationData` (same as `I18n.t`); the English fallback
  # does not fill missing plural keys.
  module Translation
    extend self

    SHIPPED_ENGLISH_MUTEX = Mutex.new
    private_constant :SHIPPED_ENGLISH_MUTEX

    def t(key, **options)
      return key.map { |entry| t(entry, **options) } if key.is_a?(Array)
      return ::I18n.t(key, **options) unless gem_key?(key, options[:scope])

      options = escape_html_interpolation(key, options)
      html_safe_translation(key, translate_gem_key(key, options), options)
    end

    # Register an additional English locale file for the final shipped-English
    # fallback table. Call this only at boot from an addon engine initializer
    # (typically `before: "recording_studio.load_shipped_english"`), not at
    # request time.
    #
    # Paths are expanded and de-duplicated. Registrations persist across Rails
    # code reloads; the merged table is rebuilt on the next load / `to_prepare`.
    # A missing or malformed file is skipped when the table is built (empty
    # contribution). +nil+ or blank paths raise +ArgumentError+.
    def register_shipped_english(path)
      raise ArgumentError, "shipped english path is required" if path.nil? || path.to_s.strip.empty?

      expanded = File.expand_path(path.to_s)
      SHIPPED_ENGLISH_MUTEX.synchronize do
        paths = (@registered_shipped_english_paths ||= [])
        paths << expanded unless paths.include?(expanded)
        @shipped_english = nil
      end
    end

    # Deep-frozen flat map of gem English under `recording_studio.*`, merged
    # from base `config/locales/en.yml` and every path registered via
    # {register_shipped_english}. Eager-loaded from the engine initializer;
    # reset on Rails code reload. Independent of the I18n backend so a pruned
    # host load path still has text.
    def shipped_english
      return @shipped_english if @shipped_english

      SHIPPED_ENGLISH_MUTEX.synchronize do
        @shipped_english ||= deep_freeze(load_shipped_english)
      end
    end

    def reset_shipped_english!
      SHIPPED_ENGLISH_MUTEX.synchronize { @shipped_english = nil }
    end

    private

    def translate_gem_key(key, options)
      locale = options[:locale] || ::I18n.locale
      scope = options[:scope]
      return ::I18n.t(key, **options) if ::I18n.exists?(key, locale, scope: scope)

      defaults = fallback_defaults(key, scope, options)
      return ::I18n.t(key, **options, default: defaults) if defaults.any?

      ::I18n.t(key, **options)
    end

    def fallback_defaults(key, scope, options)
      caller_defaults = Array(options[:default])
      shipped = shipped_english_value(key, scope)

      if ::I18n.exists?(key, :en, scope: scope)
        english = ::I18n.t(key, **options.except(:default, :raise, :locale), locale: :en)
        return [english, *caller_defaults, *Array(shipped)].compact
      end

      [*caller_defaults, *Array(shipped)].compact
    end

    def gem_key?(key, scope = nil)
      return false unless key.is_a?(String) || key.is_a?(Symbol)

      key_string = key.to_s
      return false if key_string.start_with?(".")
      return recording_studio_name?(Array(scope).join(".")) if scope

      recording_studio_name?(key_string)
    end

    def recording_studio_name?(name)
      name == "recording_studio" || name.start_with?("recording_studio.")
    end

    def shipped_english_value(key, scope = nil)
      full_key = full_gem_key(key, scope)
      full_key && shipped_english[full_key]
    end

    def full_gem_key(key, scope = nil)
      key_string = key.to_s
      return nil if key_string.start_with?(".")

      scope ? "#{Array(scope).join('.')}.#{key_string}" : key_string
    end

    def load_shipped_english
      tree = load_english_recording_studio_tree(shipped_english_path)
      registered_shipped_english_paths.each do |path|
        tree = deep_merge_hashes(tree, load_english_recording_studio_tree(path))
      end
      flatten_locale_keys(tree, ["recording_studio"])
    end

    def registered_shipped_english_paths
      @registered_shipped_english_paths ||= []
    end

    def load_english_recording_studio_tree(path)
      data = YAML.safe_load_file(path, aliases: true)
      tree = data.is_a?(Hash) ? data.dig("en", "recording_studio") : nil
      return {} unless tree.is_a?(Hash)

      tree
    rescue Errno::ENOENT
      {}
    end

    def shipped_english_path
      File.expand_path("../../config/locales/en.yml", __dir__)
    end

    def deep_merge_hashes(left, right)
      left.merge(right) do |_key, left_value, right_value|
        if left_value.is_a?(Hash) && right_value.is_a?(Hash)
          deep_merge_hashes(left_value, right_value)
        else
          right_value
        end
      end
    end

    def deep_freeze(object)
      case object
      when Hash then object.each_value { |value| deep_freeze(value) }
      when Array then object.each { |value| deep_freeze(value) }
      end
      object.freeze
    end

    def flatten_locale_keys(node, prefix)
      case node
      when Hash
        node.each_with_object({}) do |(key, value), result|
          result.merge!(flatten_locale_keys(value, prefix + [key.to_s]))
        end
      else
        { prefix.join(".") => node }
      end
    end

    def escape_html_interpolation(key, options)
      return options unless html_safe_key?(key)

      options.each_with_object({}) do |(name, value), escaped|
        escaped[name] = escape_interpolation_value(name, value)
      end
    end

    def escape_interpolation_value(name, value)
      return value if i18n_option?(name)
      return value if name == :count && value.is_a?(Numeric)

      ERB::Util.html_escape(value.to_s)
    end

    def i18n_option?(name)
      ::I18n::RESERVED_KEYS.include?(name)
    end

    def html_safe_translation(key, value, options)
      return value unless value.is_a?(String)
      return value unless html_safe_key?(key)
      return value unless value.respond_to?(:html_safe)
      return value if plain_caller_default_result?(key, value, options)

      value.html_safe
    end

    # Non-interpolating caller defaults on a missing `_html` key stay unsafe,
    # matching view `t`. Interpolating defaults that went through arg escaping
    # still get marked html_safe (stricter than view `t`).
    def plain_caller_default_result?(key, value, options)
      default = options[:default]
      return false unless default.is_a?(String)
      return false if default.match?(/%\{/)
      return false unless value == default

      !resolved_translation_present?(key, options)
    end

    def resolved_translation_present?(key, options)
      locale = options[:locale] || ::I18n.locale
      scope = options[:scope]
      ::I18n.exists?(key, locale, scope: scope) ||
        ::I18n.exists?(key, :en, scope: scope) ||
        !shipped_english_value(key, scope).nil?
    end

    def html_safe_key?(key)
      key.to_s.match?(/(?:\b|_)html\z/)
    end
  end

  def self.t(...)
    Translation.t(...)
  end
end

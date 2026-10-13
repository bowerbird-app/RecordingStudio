# frozen_string_literal: true

module RecordingStudio
  # Locale lookups for gem-shipped `recording_studio.*` keys.
  #
  # When the active locale has no translation, falls back to the loaded `:en`
  # value (host English overrides included) so hosts without a translated file
  # do not see "Translation missing" or raise. Non-gem keys, present locale
  # values, caller `default:` / `raise:` / `locale:`, Arrays, and lazy keys
  # pass through like `I18n.t`.
  module Translation
    extend self

    def t(key, **options)
      return key.map { |entry| t(entry, **options) } if key.is_a?(Array)
      return ::I18n.t(key, **options) unless gem_key?(key, options[:scope])

      html_safe_translation(key, translate_gem_key(key, options))
    end

    private

    def translate_gem_key(key, options)
      locale = options[:locale] || ::I18n.locale
      return ::I18n.t(key, **options) if locale.to_s == "en"
      return ::I18n.t(key, **options) if ::I18n.exists?(key, locale, scope: options[:scope])
      return ::I18n.t(key, **options) unless ::I18n.exists?(key, :en, scope: options[:scope])

      english = ::I18n.t(key, **options.except(:default, :raise, :locale), locale: :en)
      ::I18n.t(key, **options, default: [english, *Array(options[:default])])
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

    def html_safe_translation(key, value)
      return value unless value.is_a?(String)
      return value unless html_safe_key?(key)
      return value unless value.respond_to?(:html_safe)

      value.html_safe
    end

    def html_safe_key?(key)
      key.to_s.match?(/(\b|_|\.)html\z/)
    end
  end

  def self.t(...)
    Translation.t(...)
  end
end

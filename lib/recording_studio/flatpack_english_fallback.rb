# frozen_string_literal: true

module RecordingStudio
  # FlatPack looks up `flatpack.*` through I18n, not RecordingStudio.t.
  # Locales in this app do not fall back to English, so a new FlatPack key
  # renders "Translation missing" until a host translates it. Use the loaded
  # English string for those misses. A present locale value still wins.
  class FlatpackEnglishFallback
    LOOKUP_OPTIONS = %i[default raise locale throw exception_handler].freeze

    def self.install!
      handler = I18n.exception_handler
      return if handler.is_a?(self)

      I18n.exception_handler = new(handler)
    end

    def initialize(previous)
      @previous = previous
    end

    def call(exception, locale, key, options)
      english = english_flatpack(exception, locale, key, options)
      return english unless english.nil?

      @previous.call(exception, locale, key, options)
    end

    private

    def english_flatpack(exception, locale, key, options)
      return unless missing_flatpack?(exception, locale, key, options)

      ::I18n.t(key, **english_options(options))
    end

    def missing_flatpack?(exception, locale, key, options)
      exception.is_a?(::I18n::MissingTranslation) &&
        locale.to_sym != :en &&
        flatpack_lookup?(key, options) &&
        ::I18n.exists?(key, :en, scope: options[:scope])
    end

    def english_options(options)
      options.except(*LOOKUP_OPTIONS).merge(locale: :en, scope: options[:scope], raise: true)
    end

    def flatpack_lookup?(key, options)
      scoped_key(key, options).start_with?("flatpack.")
    end

    def scoped_key(key, options)
      [scope_string(options[:scope]), key].compact.reject { |part| part.to_s.empty? }.join(".")
    end

    def scope_string(scope)
      case scope
      when Array then scope.join(".")
      when nil, "" then nil
      else scope.to_s
      end
    end
  end
end

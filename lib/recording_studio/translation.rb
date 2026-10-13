# frozen_string_literal: true

module RecordingStudio
  # Locale lookups for gem-shipped `recording_studio.*` keys.
  #
  # When the active locale has no translation, falls back to the gem's English
  # value from `config/locales/en.yml` (via `locale: :en`) so hosts without a
  # translated file do not see "Translation missing" or raise. Host overrides
  # in the active locale still win because they resolve before the default.
  module Translation
    module_function

    def t(key, **options)
      options = options.dup
      options.delete(:default)
      english = ::I18n.t(key, **options, locale: :en, raise: true)
      ::I18n.t(key, **options, default: english)
    end
  end

  def self.t(...)
    Translation.t(...)
  end
end

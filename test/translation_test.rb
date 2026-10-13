# frozen_string_literal: true

require "test_helper"

class TranslationTest < ActiveSupport::TestCase
  GEM_KEYS = {
    "recording_studio.core.navigation.back" => "Back",
    "recording_studio.core.navigation.go_back" => "Go back",
    "recording_studio.core.navigation.close" => "Close",
    "recording_studio.core.navigation.page" => "Page navigation",
    "recording_studio.core.navigation.action_page" => "Action page navigation",
    "recording_studio.core.labels.empty" => "—"
  }.freeze

  test "english locale resolves every shipped gem key from en.yml" do
    I18n.with_locale(:en) do
      GEM_KEYS.each do |key, english|
        assert_equal english, RecordingStudio.t(key)
        assert_equal english, RecordingStudio::Translation.t(key)
      end
    end
  end

  test "missing locale falls back to gem english from en.yml" do
    previous_locales = I18n.available_locales
    I18n.available_locales = (previous_locales + %i[en fr]).uniq

    I18n.with_locale(:fr) do
      GEM_KEYS.each do |key, english|
        refute I18n.exists?(key, :fr), "#{key} must be absent in :fr for this test"
        assert_equal english, RecordingStudio.t(key),
                     "#{key} should fall back to gem English when :fr has no file"
        refute_match(/translation missing/i, RecordingStudio.t(key))
      end
    end
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  test "host override in active locale wins over english fallback" do
    previous_locales = I18n.available_locales
    I18n.available_locales = (previous_locales + %i[en fr]).uniq
    I18n.backend.store_translations(:fr, {
                                      recording_studio: {
                                        core: {
                                          navigation: { go_back: "HOST Retour" },
                                          labels: { empty: "HOST VIDE" }
                                        }
                                      }
                                    })

    I18n.with_locale(:fr) do
      assert_equal "HOST Retour", RecordingStudio.t("recording_studio.core.navigation.go_back")
      assert_equal "HOST VIDE", RecordingStudio.t("recording_studio.core.labels.empty")
      assert_equal "Close", RecordingStudio.t("recording_studio.core.navigation.close"),
                   "unoverridden keys still fall back to gem English"
    end
  ensure
    I18n.available_locales = previous_locales if previous_locales
    I18n.reload!
  end

  test "does not raise for missing locale when callers use raise-on-missing style lookups" do
    previous_locales = I18n.available_locales
    I18n.available_locales = (previous_locales + %i[en fr]).uniq

    I18n.with_locale(:fr) do
      assert_raises(I18n::MissingTranslationData) do
        I18n.t("recording_studio.core.navigation.go_back", locale: :fr, raise: true)
      end

      assert_equal "Go back", RecordingStudio.t("recording_studio.core.navigation.go_back")
    end
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  test "english fallback value matches en.yml not a ruby literal table" do
    en_yml = YAML.safe_load_file(
      File.expand_path("../config/locales/en.yml", __dir__),
      aliases: true
    )
    gem_english = en_yml.fetch("en").fetch("recording_studio").fetch("core")
                        .fetch("navigation").fetch("go_back")

    source = File.read(File.expand_path("../lib/recording_studio/translation.rb", __dir__))
    refute_includes source, gem_english,
                    "Translation helper must not hard-code English; it must read en.yml via locale: :en"

    previous_locales = I18n.available_locales
    I18n.available_locales = (previous_locales + %i[en fr]).uniq
    I18n.with_locale(:fr) do
      assert_equal gem_english, RecordingStudio.t("recording_studio.core.navigation.go_back")
    end
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end
end

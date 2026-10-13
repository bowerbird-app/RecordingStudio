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

  setup do
    @previous_locales = I18n.available_locales
    I18n.available_locales = (@previous_locales + %i[en fr de xx]).uniq
  end

  teardown do
    I18n.locale = I18n.default_locale
    I18n.available_locales = @previous_locales if @previous_locales
    I18n.reload!
  end

  test "english locale resolves every shipped gem key from en.yml" do
    I18n.with_locale(:en) do
      GEM_KEYS.each do |key, english|
        assert_equal english, RecordingStudio.t(key)
        assert_equal english, RecordingStudio::Translation.t(key)
      end
    end
  end

  test "missing locale falls back to loaded english" do
    I18n.with_locale(:de) do
      GEM_KEYS.each do |key, english|
        refute I18n.exists?(key, :de), "#{key} must be absent in :de for this test"
        assert_equal english, RecordingStudio.t(key),
                     "#{key} should fall back to loaded English when :de has no file"
        refute_match(/translation missing/i, RecordingStudio.t(key))
      end
    end
  end

  test "host override in active locale wins over english fallback" do
    I18n.with_locale(:fr) do
      assert I18n.exists?("recording_studio.core.navigation.go_back", :fr),
             "boot-loaded zz_core_host_override.fr.yml must provide :fr keys"
      assert_equal "HOST Retour", RecordingStudio.t("recording_studio.core.navigation.go_back")
      assert_equal "HOST VIDE", RecordingStudio.t("recording_studio.core.labels.empty")
      assert_equal "HOST Fermer", RecordingStudio.t("recording_studio.core.navigation.close")
    end
  end

  test "does not raise for missing locale when callers use raise-on-missing style lookups" do
    I18n.with_locale(:de) do
      assert_raises(I18n::MissingTranslationData) do
        I18n.t("recording_studio.core.navigation.go_back", locale: :de, raise: true)
      end

      assert_equal "Go back", RecordingStudio.t("recording_studio.core.navigation.go_back")
    end
  end

  test "english fallback value matches loaded en backend not a ruby literal table" do
    en_yml = YAML.safe_load_file(
      File.expand_path("../config/locales/en.yml", __dir__),
      aliases: true
    )
    gem_english = en_yml.fetch("en").fetch("recording_studio").fetch("core")
                        .fetch("navigation").fetch("go_back")

    source = File.read(File.expand_path("../lib/recording_studio/translation.rb", __dir__))
    refute_includes source, gem_english,
                    "Translation helper must not hard-code English; it must read loaded :en"

    I18n.with_locale(:de) do
      assert_equal gem_english, RecordingStudio.t("recording_studio.core.navigation.go_back")
    end
  end

  test "parity matrix non-gem keys match I18n.t" do
    I18n.backend.store_translations(:en, {
                                      probe: {
                                        greet: "Hi %{name}",
                                        empty: "",
                                        nil_value: nil,
                                        nest: { a: "A" },
                                        html_key_html: "<b>x</b>",
                                        items: { one: "one item", other: "%{count} items" }
                                      }
                                    })
    I18n.backend.store_translations(:de, { probe: { greet: "Hallo %{name}" } })

    I18n.with_locale(:de) do
      assert_parity("probe.greet", name: "M")
      assert_parity("probe.missing")
      assert_parity("probe.missing", default: "D")
      assert_parity("probe.empty")
      assert_parity("probe.nil_value")
      assert_parity("probe.nest")
      assert_parity("probe.items", count: 1)
      assert_parity("probe.items", count: 5)
      assert_parity(:"probe.greet", name: "M")
      assert_parity(%w[probe.missing probe.greet], name: "M")
      assert_parity("greet", scope: "probe", name: "M")
      assert_raise_parity("probe.missing", raise: true)
      assert_parity("probe.greet", locale: :en, name: "M")
      assert_parity("probe.html_key_html")
    end
  end

  test "parity matrix gem keys cover missing default raise nil empty hash and related options" do
    key = "recording_studio.core.navigation.go_back"
    missing = "recording_studio.core.navigation.missing_key_for_parity"

    I18n.backend.store_translations(:en, {
                                      recording_studio: {
                                        core: {
                                          navigation: {
                                            nil_value: nil,
                                            empty_value: "",
                                            nest: { a: "A" },
                                            html_key_html: "<i>g</i>",
                                            items: { one: "one", other: "%{count} many" },
                                            greet: "Hi %{name}"
                                          }
                                        }
                                      }
                                    })

    I18n.with_locale(:en) do
      assert_equal I18n.t(key), RecordingStudio.t(key)
      assert_equal "Go back", RecordingStudio.t(key, default: "Ignored when present")
    end

    I18n.with_locale(:de) do
      assert_equal "Go back", RecordingStudio.t(key),
                   "missing active locale uses loaded English"
      assert_match(/translation missing/i, I18n.t(key))

      assert_parity(missing)
      assert_parity(missing, default: "D")
      assert_raise_parity(missing, raise: true)

      I18n.backend.store_translations(:de, {
                                        recording_studio: { core: { navigation: { go_back: "DE Zurück" } } }
                                      })
      assert_equal "DE Zurück", RecordingStudio.t(key)
      assert_equal I18n.t(key), RecordingStudio.t(key),
                   "no English fallback when the active locale has the key"

      # Nil in en is treated as missing by I18n.exists?, so both helpers match.
      assert_parity("recording_studio.core.navigation.nil_value")
      # Empty string exists in en and is a valid fallback value.
      assert_equal "", RecordingStudio.t("recording_studio.core.navigation.empty_value")
      assert_match(/translation missing/i, I18n.t("recording_studio.core.navigation.empty_value"))

      assert_equal(
        I18n.t("recording_studio.core.navigation.nest", locale: :en),
        RecordingStudio.t("recording_studio.core.navigation.nest")
      )
      assert_equal(
        I18n.t("recording_studio.core.navigation.items", locale: :en, count: 1),
        RecordingStudio.t("recording_studio.core.navigation.items", count: 1)
      )
      assert_equal(
        I18n.t("recording_studio.core.navigation.greet", locale: :en, name: "M"),
        RecordingStudio.t("recording_studio.core.navigation.greet", name: "M")
      )

      assert_equal "DE Zurück", RecordingStudio.t(:"recording_studio.core.navigation.go_back")
      assert_equal(
        ["DE Zurück", "Close"],
        RecordingStudio.t(%w[
                            recording_studio.core.navigation.go_back
                            recording_studio.core.navigation.close
                          ])
      )
      assert_equal "DE Zurück", RecordingStudio.t(:go_back, scope: "recording_studio.core.navigation")

      html = RecordingStudio.t("recording_studio.core.navigation.html_key_html")
      assert_equal "<i>g</i>", html
      assert_predicate html, :html_safe?

      # Absent in en → caller default wins (same as I18n.t)
      assert_equal "D", RecordingStudio.t(missing, default: "D")

      # Present in en → English comes before caller default
      I18n.backend.store_translations(:en, {
                                        recording_studio: {
                                          core: { navigation: { missing_key_for_parity: "EN" } }
                                        }
                                      })
      assert_equal "EN", RecordingStudio.t(missing, default: "D")

      error = assert_raises(I18n::MissingTranslationData) do
        RecordingStudio.t("recording_studio.core.navigation.totally_absent", raise: true)
      end
      assert_match(/Translation missing: de\.recording_studio/, error.message)

      assert_equal "Go back", RecordingStudio.t(key, locale: :en)
    end
  end

  test "lazy keys pass through like I18n.t" do
    I18n.with_locale(:en) do
      assert_equal I18n.t(".lazy_key_without_scope"), RecordingStudio.t(".lazy_key_without_scope")
    end
  end

  test "global I18n config snapshot is unchanged by RecordingStudio.t" do
    before = i18n_config_snapshot

    RecordingStudio.t("recording_studio.core.navigation.back")
    I18n.with_locale(:de) do
      RecordingStudio.t("recording_studio.core.navigation.back")
      RecordingStudio.t("not_a_gem_key")
    end

    assert_equal before, i18n_config_snapshot
  end

  test "global I18n config keeps fallbacks load_path available_locales and exception handler" do
    snapshot = i18n_config_snapshot
    gem_en = File.expand_path("../config/locales/en.yml", __dir__)
    host_fr = File.expand_path("dummy/config/locales/zz_core_host_override.fr.yml", __dir__)

    assert_includes snapshot.fetch(:load_path), File.expand_path(gem_en)
    assert_includes snapshot.fetch(:load_path), File.expand_path(host_fr)
    assert_operator snapshot.fetch(:load_path).index(File.expand_path(gem_en)),
                    :<,
                    snapshot.fetch(:load_path).index(File.expand_path(host_fr))
    assert_equal [:de], snapshot.fetch(:fallbacks_de)
    assert_equal [:fr], snapshot.fetch(:fallbacks_fr)
    assert snapshot.fetch(:exception_handler), "expected an I18n exception handler"
    assert_includes snapshot.fetch(:available_locales), :en
    assert_includes snapshot.fetch(:available_locales), :fr
  end

  private

  def assert_parity(key, **options)
    expected = I18n.t(key, **options)
    actual = RecordingStudio.t(key, **options)
    assert_equal expected, actual, "parity failed for #{key.inspect} options=#{options.inspect}"
    return unless actual.is_a?(String) && key.to_s.match?(/(\b|_|\.)html\z/)

    assert_equal expected.html_safe?, actual.html_safe?
  end

  def assert_raise_parity(key, **options)
    i18n_error = assert_raises(I18n::MissingTranslationData) { I18n.t(key, **options) }
    rs_error = assert_raises(I18n::MissingTranslationData) { RecordingStudio.t(key, **options) }
    assert_equal i18n_error.message, rs_error.message
  end

  def i18n_config_snapshot
    {
      load_path: I18n.load_path.map { |path| File.expand_path(path) },
      available_locales: Array(I18n.available_locales).map(&:to_sym).sort,
      exception_handler: I18n.exception_handler,
      enforce_available_locales: I18n.enforce_available_locales,
      fallbacks_class: (I18n.fallbacks.class.name if I18n.respond_to?(:fallbacks)),
      fallbacks_de: (I18n.fallbacks[:de].dup if I18n.respond_to?(:fallbacks)),
      fallbacks_fr: (I18n.fallbacks[:fr].dup if I18n.respond_to?(:fallbacks)),
      fallbacks_en: (I18n.fallbacks[:en].dup if I18n.respond_to?(:fallbacks))
    }
  end
end

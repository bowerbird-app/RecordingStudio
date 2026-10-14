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

  test "shipped english table matches gem en.yml and is reused across calls" do
    RecordingStudio::Translation.reset_shipped_english!
    en_yml = YAML.safe_load_file(
      File.expand_path("../config/locales/en.yml", __dir__),
      aliases: true
    ).fetch("en").fetch("recording_studio")

    expected = flatten_locale_keys(en_yml, ["recording_studio"])
    table = RecordingStudio::Translation.shipped_english
    assert_equal expected, table
    assert_predicate table, :frozen?
    table.each_value { |value| assert_predicate value, :frozen? }
    assert_same table, RecordingStudio::Translation.shipped_english,
                "shipped english must be reused across calls (no per-call file reload)"
  end

  test "deleted loaded english falls back to shipped gem en.yml text" do
    GEM_KEYS.each_key do |key|
      delete_loaded_translation!(:en, key)
      delete_loaded_translation!(:fr, key)
    end

    GEM_KEYS.each do |key, english|
      refute I18n.exists?(key, :en), "#{key} must be absent from loaded :en"
      I18n.with_locale(:en) do
        assert_equal english, RecordingStudio.t(key)
        refute_match(/translation missing/i, RecordingStudio.t(key))
      end
      I18n.with_locale(:fr) do
        assert_equal english, RecordingStudio.t(key)
        refute_match(/translation missing/i, RecordingStudio.t(key))
      end
    end
  ensure
    I18n.reload!
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

      # scope: when the active locale lacks the key → English / shipped fallback
      assert_equal(
        "Close",
        RecordingStudio.t(:close, scope: "recording_studio.core.navigation"),
        "scope: gem key missing in :de must fall back to English"
      )

      html = RecordingStudio.t("recording_studio.core.navigation.html_key_html")
      assert_equal "<i>g</i>", html
      assert_predicate html, :html_safe?

      # Absent in en and shipped → caller default wins (same as I18n.t)
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

  test "fallback order prefers loaded english then caller default over shipped table" do
    key = "recording_studio.core.navigation.back"

    write_loaded_translation!(:en, key, "HOST EN Back")
    I18n.with_locale(:de) do
      refute I18n.exists?(key, :de)
      assert_equal "HOST EN Back", RecordingStudio.t(key),
                   "host :en override must win over the gem-shipped table"
    end

    delete_loaded_translation!(:en, key)
    delete_loaded_translation!(:fr, key)
    %i[en fr de].each do |locale|
      I18n.with_locale(locale) do
        assert_equal "CALLER", RecordingStudio.t(key, default: "CALLER"),
                     "caller default: must come before the gem-shipped table in #{locale}"
      end
    end
  ensure
    I18n.reload!
  end

  test "html gem keys escape unsafe interpolation like view t" do
    I18n.backend.store_translations(:en, {
                                      recording_studio: {
                                        probe: {
                                          hi_html: "<b>Hi %{name}</b>",
                                          greet: "Hi %{name}",
                                          items_html: {
                                            one: "<i>1 x</i>",
                                            other: "<i>%{count} xs</i>"
                                          }
                                        }
                                      }
                                    })
    view = ActionController::Base.helpers

    I18n.with_locale(:en) do
      value = RecordingStudio.t("recording_studio.probe.hi_html", name: "<script>")
      assert_equal "<b>Hi &lt;script&gt;</b>", value
      assert_predicate value, :html_safe?
      assert_equal view.t("recording_studio.probe.hi_html", name: "<script>"), value

      plain = RecordingStudio.t("recording_studio.probe.greet", name: "<s>")
      assert_equal "Hi <s>", plain
      refute_predicate plain, :html_safe?
      assert_equal view.t("recording_studio.probe.greet", name: "<s>"), plain

      safe_arg = "<u>ok</u>".html_safe
      with_safe = RecordingStudio.t("recording_studio.probe.hi_html", name: safe_arg)
      assert_equal "<b>Hi <u>ok</u></b>", with_safe
      assert_equal view.t("recording_studio.probe.hi_html", name: safe_arg), with_safe

      plural = RecordingStudio.t("recording_studio.probe.items_html", count: 2)
      assert_equal "<i>2 xs</i>", plural
      assert_predicate plural, :html_safe?
      assert_equal view.t("recording_studio.probe.items_html", count: 2), plural

      singular = RecordingStudio.t("recording_studio.probe.items_html", count: 1)
      assert_equal "<i>1 x</i>", singular
      assert_predicate singular, :html_safe?
      assert_equal view.t("recording_studio.probe.items_html", count: 1), singular

      # Reserved options (default:) are not html-escaped as interpolation values.
      # A non-interpolating caller default on a missing _html key stays unsafe
      # like view t.
      missing_html = "recording_studio.probe.missing_key_html"
      reserved = RecordingStudio.t(missing_html, default: "<b>ok</b>")
      assert_equal "<b>ok</b>", reserved
      refute_predicate reserved, :html_safe?
      assert_equal view.t(missing_html, default: "<b>ok</b>"), reserved
    end
  end

  test "shipped english table is present after boot" do
    refute_nil RecordingStudio::Translation.instance_variable_get(:@shipped_english),
               "engine initializer / to_prepare must eager-load shipped english before any call"
    assert_includes RecordingStudio::Engine.initializers.map(&:name),
                    "recording_studio.load_shipped_english",
                    "engine must register the load_shipped_english initializer"
    table = RecordingStudio::Translation.shipped_english
    refute_empty table
    assert_equal "Back", table.fetch("recording_studio.core.navigation.back")
  end

  test "shipped english table becomes a new object after reload reset" do
    before = RecordingStudio::Translation.shipped_english
    Rails.application.reloader.reload!
    after = RecordingStudio::Translation.shipped_english

    refute_same before, after
    assert_equal before, after
    assert_predicate after, :frozen?
  end

  test "missing shipped en.yml boots with empty frozen table matching I18n.t" do
    missing_path = File.expand_path("../tmp/missing_shipped_en_#{Process.pid}.yml", __dir__)
    refute File.exist?(missing_path), "stub path must not exist"

    with_missing_shipped_english_path(missing_path) do
      table = RecordingStudio::Translation.shipped_english
      assert_equal({}, table)
      assert_predicate table, :frozen?

      missing = "recording_studio.core.navigation.totally_absent_for_missing_yml"
      %i[en fr de].each do |locale|
        I18n.with_locale(locale) do
          assert_equal I18n.t(missing), RecordingStudio.t(missing)
          assert_equal I18n.t(missing, default: "D"), RecordingStudio.t(missing, default: "D")
          i18n_error = assert_raises(I18n::MissingTranslationData) do
            I18n.t(missing, raise: true)
          end
          rs_error = assert_raises(I18n::MissingTranslationData) do
            RecordingStudio.t(missing, raise: true)
          end
          assert_equal i18n_error.message, rs_error.message
        end
      end
    end
  end

  test "register_shipped_english adds path to merged fallback table" do
    with_registered_shipped_english_fixture(
      "en" => {
        "recording_studio" => {
          "probe_engine" => { "greeting" => "Hello from probe engine" }
        }
      }
    ) do |path|
      RecordingStudio::Translation.register_shipped_english(path)
      table = RecordingStudio::Translation.shipped_english

      assert_equal "Hello from probe engine",
                   table.fetch("recording_studio.probe_engine.greeting")
      assert_equal "Back", table.fetch("recording_studio.core.navigation.back"),
                   "base en.yml keys must remain after registration"
      assert_equal "Hello from probe engine",
                   RecordingStudio.t("recording_studio.probe_engine.greeting")
    end
  end

  test "register_shipped_english de-duplicates the same expanded path" do
    with_shipped_english_registrations([]) do
      with_registered_shipped_english_fixture(
        "en" => {
          "recording_studio" => {
            "probe_engine" => { "once" => "only once" }
          }
        }
      ) do |path|
        RecordingStudio::Translation.register_shipped_english(path)
        RecordingStudio::Translation.register_shipped_english(path)
        RecordingStudio::Translation.register_shipped_english(
          Pathname.new(path).relative_path_from(Pathname.pwd).to_s
        )

        paths = RecordingStudio::Translation.send(:registered_shipped_english_paths)
        assert_equal 1, paths.size, "exact total registered path count must stay 1 after de-dupe"
        assert_equal File.expand_path(path), paths.first
        assert_equal "only once",
                     RecordingStudio::Translation.shipped_english.fetch(
                       "recording_studio.probe_engine.once"
                     )
      end
    end
  end

  test "missing registered shipped english path is skipped without raising" do
    missing = File.expand_path("../tmp/missing_registered_en_#{Process.pid}.yml", __dir__)
    refute File.exist?(missing)

    with_shipped_english_registrations([]) do
      assert_nothing_raised do
        RecordingStudio::Translation.register_shipped_english(missing)
        table = RecordingStudio::Translation.shipped_english
        assert_equal "Back", table.fetch("recording_studio.core.navigation.back")
        refute table.key?("recording_studio.missing.registered")
      end
    end
  end

  test "register_shipped_english nil path raises ArgumentError" do
    error = assert_raises(ArgumentError) do
      RecordingStudio::Translation.register_shipped_english(nil)
    end
    assert_match(/shipped english path is required/i, error.message)
  end

  test "register_shipped_english blank path raises ArgumentError" do
    ["", "   ", "\t\n"].each do |blank|
      error = assert_raises(ArgumentError) do
        RecordingStudio::Translation.register_shipped_english(blank)
      end
      assert_match(/shipped english path is required/i, error.message)
    end
  end

  test "malformed registered en.yml without en root is skipped without raising" do
    assert_malformed_registered_shipped_english_skipped(
      { "fr" => { "recording_studio" => { "probe" => "nope" } } },
      "recording_studio.probe"
    )
  end

  test "malformed registered en.yml without recording_studio key is skipped without raising" do
    assert_malformed_registered_shipped_english_skipped(
      { "en" => { "other" => { "probe" => "nope" } } },
      "recording_studio.other.probe"
    )
  end

  test "malformed registered en.yml with nil recording_studio value is skipped without raising" do
    assert_malformed_registered_shipped_english_skipped(
      { "en" => { "recording_studio" => nil } },
      "recording_studio.probe"
    )
  end

  test "malformed registered en.yml with string recording_studio value is skipped without raising" do
    assert_malformed_registered_shipped_english_skipped(
      { "en" => { "recording_studio" => "not a hash" } },
      "recording_studio.probe"
    )
  end

  test "malformed registered empty en.yml file is skipped without raising" do
    with_raw_registered_shipped_english_file("") do |path|
      with_shipped_english_registrations([]) do
        assert_nothing_raised do
          RecordingStudio::Translation.register_shipped_english(path)
          table = RecordingStudio::Translation.shipped_english
          assert_equal "Back", table.fetch("recording_studio.core.navigation.back")
        end
      end
    end
  end

  test "reload rebuilds shipped english table from edited registration file" do
    with_registered_shipped_english_fixture(
      "en" => {
        "recording_studio" => {
          "probe_engine" => { "reload" => "before reload" }
        }
      }
    ) do |path|
      RecordingStudio::Translation.register_shipped_english(path)
      before = RecordingStudio::Translation.shipped_english
      assert_equal "before reload", before.fetch("recording_studio.probe_engine.reload")

      File.write(
        path,
        YAML.dump(
          "en" => {
            "recording_studio" => {
              "probe_engine" => { "reload" => "after reload edit" }
            }
          }
        )
      )

      Rails.application.reloader.reload!
      after = RecordingStudio::Translation.shipped_english

      refute_same before, after
      assert_equal "after reload edit", after.fetch("recording_studio.probe_engine.reload")
      assert_includes RecordingStudio::Translation.send(:registered_shipped_english_paths),
                      File.expand_path(path)
      assert_predicate after, :frozen?
    end
  end

  test "overlapping registered engines deep merge later wins and keep siblings" do
    fixture_a = {
      "en" => {
        "recording_studio" => {
          "shared" => {
            "conflict" => "from A",
            "sibling_a" => "A only"
          }
        }
      }
    }
    fixture_b = {
      "en" => {
        "recording_studio" => {
          "shared" => {
            "conflict" => "from B",
            "sibling_b" => "B only"
          }
        }
      }
    }

    with_shipped_english_registrations([]) do
      with_registered_shipped_english_fixture(fixture_a) do |path_a|
        with_registered_shipped_english_fixture(fixture_b) do |path_b|
          RecordingStudio::Translation.register_shipped_english(path_a)
          RecordingStudio::Translation.register_shipped_english(path_b)

          paths = RecordingStudio::Translation.send(:registered_shipped_english_paths)
          assert_equal 2, paths.size, "exact total registered path count must be 2"
          assert_equal [File.expand_path(path_a), File.expand_path(path_b)], paths

          table = RecordingStudio::Translation.shipped_english
          assert_equal "from B", table.fetch("recording_studio.shared.conflict"),
                       "later registration must win on conflicting keys"
          assert_equal "A only", table.fetch("recording_studio.shared.sibling_a"),
                       "deep merge must keep earlier siblings"
          assert_equal "B only", table.fetch("recording_studio.shared.sibling_b"),
                       "deep merge must keep later siblings"
        end
      end
    end
  end

  test "register after building shipped english table exposes new keys without reset" do
    with_registered_shipped_english_fixture(
      "en" => {
        "recording_studio" => {
          "probe_engine" => { "late" => "registered after build" }
        }
      }
    ) do |path|
      before = RecordingStudio::Translation.shipped_english
      refute before.key?("recording_studio.probe_engine.late")

      RecordingStudio::Translation.register_shipped_english(path)
      after = RecordingStudio::Translation.shipped_english

      refute_same before, after
      assert_equal "registered after build",
                   after.fetch("recording_studio.probe_engine.late")
      assert_equal "registered after build",
                   RecordingStudio.t("recording_studio.probe_engine.late")
    end
  end

  test "two registered engines with disjoint keys resolve after backend delete" do
    fixture_a = {
      "en" => {
        "recording_studio" => {
          "fake_engine_a" => { "label" => "Engine A English" }
        }
      }
    }
    fixture_b = {
      "en" => {
        "recording_studio" => {
          "fake_engine_b" => { "label" => "Engine B English" }
        }
      }
    }

    with_registered_shipped_english_fixture(fixture_a) do |path_a|
      with_registered_shipped_english_fixture(fixture_b) do |path_b|
        RecordingStudio::Translation.register_shipped_english(path_a)
        RecordingStudio::Translation.register_shipped_english(path_b)

        key_a = "recording_studio.fake_engine_a.label"
        key_b = "recording_studio.fake_engine_b.label"

        I18n.backend.store_translations(:en, {
                                          recording_studio: {
                                            fake_engine_a: { label: "LOADED A" },
                                            fake_engine_b: { label: "LOADED B" }
                                          }
                                        })
        assert_equal "LOADED A", RecordingStudio.t(key_a)
        assert_equal "LOADED B", RecordingStudio.t(key_b)

        delete_loaded_translation!(:en, key_a)
        delete_loaded_translation!(:en, key_b)
        delete_loaded_translation!(:fr, key_a)
        delete_loaded_translation!(:fr, key_b)

        refute I18n.exists?(key_a, :en)
        refute I18n.exists?(key_b, :en)

        %i[en fr de].each do |locale|
          I18n.with_locale(locale) do
            assert_equal "Engine A English", RecordingStudio.t(key_a)
            assert_equal "Engine B English", RecordingStudio.t(key_b)
          end
        end
      end
    end
  ensure
    I18n.reload!
  end

  test "merged shipped english table is deep-frozen" do
    with_registered_shipped_english_fixture(
      "en" => {
        "recording_studio" => {
          "probe_engine" => { "frozen" => "ice" }
        }
      }
    ) do |path|
      RecordingStudio::Translation.register_shipped_english(path)
      table = RecordingStudio::Translation.shipped_english

      assert_predicate table, :frozen?
      table.each_value { |value| assert_predicate value, :frozen? }
      assert_raises(FrozenError) { table["recording_studio.probe_engine.frozen"] = "nope" }
    end
  end

  test "shipped english registration is thread-safe under concurrent access" do
    with_registered_shipped_english_fixture(
      "en" => {
        "recording_studio" => {
          "probe_engine" => { "thread" => "safe" }
        }
      }
    ) do |path|
      RecordingStudio::Translation.register_shipped_english(path)
      RecordingStudio::Translation.shipped_english

      errors = Queue.new
      readers = 4.times.map do
        Thread.new do
          80.times do
            table = RecordingStudio::Translation.shipped_english
            raise "not frozen" unless table.frozen?
            raise "incomplete table" unless table["recording_studio.core.navigation.back"] == "Back"
            raise "missing registered key" unless table["recording_studio.probe_engine.thread"] == "safe"
          end
        rescue StandardError => e
          errors << e
        end
      end

      writers = 4.times.map do
        Thread.new do
          40.times do
            RecordingStudio::Translation.register_shipped_english(path)
            RecordingStudio::Translation.shipped_english
          end
        rescue StandardError => e
          errors << e
        end
      end

      writers.each(&:join)
      readers.each(&:join)

      assert_empty(errors.size.times.map { errors.pop }, "reader/writer registration must not race")
      paths = RecordingStudio::Translation.send(:registered_shipped_english_paths)
      assert_equal(1, paths.count { |entry| entry == File.expand_path(path) })
      table = RecordingStudio::Translation.shipped_english
      assert_predicate table, :frozen?
      assert_equal "safe", table.fetch("recording_studio.probe_engine.thread")
      assert_equal "Back", table.fetch("recording_studio.core.navigation.back")
    end
  end

  test "present keys stay byte-identical to I18n.t with registrations loaded" do
    with_registered_shipped_english_fixture(
      "en" => {
        "recording_studio" => {
          "probe_engine" => { "extra" => "Extra shipped" }
        }
      }
    ) do |path|
      RecordingStudio::Translation.register_shipped_english(path)

      GEM_KEYS.each_key do |key|
        I18n.with_locale(:en) do
          expected = I18n.t(key)
          actual = RecordingStudio.t(key)
          assert_equal expected, actual
          assert_equal expected.bytes, actual.bytes
        end
      end

      I18n.backend.store_translations(:en, {
                                        recording_studio: {
                                          probe_engine: { extra: "LOADED Extra" }
                                        }
                                      })
      I18n.with_locale(:en) do
        expected = I18n.t("recording_studio.probe_engine.extra")
        actual = RecordingStudio.t("recording_studio.probe_engine.extra")
        assert_equal "LOADED Extra", actual
        assert_equal expected, actual
        assert_equal expected.bytes, actual.bytes
      end
    end
  ensure
    I18n.reload!
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

  # Mutate the initialized backend hash. store_translations after I18n.reload!
  # is unreliable because the next lookup re-inits from load_path.
  def delete_loaded_translation!(locale, full_key)
    mutate_loaded_translation!(locale, full_key) { |node, leaf| node.delete(leaf) }
  end

  def write_loaded_translation!(locale, full_key, value)
    mutate_loaded_translation!(locale, full_key) { |node, leaf| node[leaf] = value }
  end

  def mutate_loaded_translation!(locale, full_key)
    I18n.exists?(full_key, locale) # ensure translations are loaded
    parts = full_key.split(".").map(&:to_sym)
    leaf = parts.pop
    translations = I18n.backend.send(:translations)
    locale_key = locale.to_sym
    translations[locale_key] = translations[locale_key].dup if translations[locale_key].frozen?

    node = translations[locale_key]
    parts.each do |part|
      break unless node.is_a?(Hash) && node[part].is_a?(Hash)

      node[part] = node[part].dup if node[part].frozen?
      node = node[part]
    end
    yield node, leaf if node.is_a?(Hash)
  end

  def with_missing_shipped_english_path(missing_path)
    translation = RecordingStudio::Translation
    singleton = class << translation; self; end
    singleton.alias_method :__original_shipped_english_path, :shipped_english_path
    singleton.define_method(:shipped_english_path) { missing_path }
    singleton.send(:private, :shipped_english_path)

    translation.reset_shipped_english!
    yield
  ensure
    if singleton.private_method_defined?(:__original_shipped_english_path) ||
       singleton.method_defined?(:__original_shipped_english_path)
      singleton.alias_method :shipped_english_path, :__original_shipped_english_path
      singleton.send(:private, :shipped_english_path)
      singleton.remove_method :__original_shipped_english_path
    end
    translation.reset_shipped_english!
    translation.shipped_english
  end

  def with_registered_shipped_english_fixture(tree)
    with_raw_registered_shipped_english_file(YAML.dump(tree)) do |path|
      with_shipped_english_registrations(
        RecordingStudio::Translation.send(:registered_shipped_english_paths).dup
      ) do
        yield path
      end
    end
  end

  def with_raw_registered_shipped_english_file(contents)
    dir = File.expand_path("../tmp/shipped_english_fixtures", __dir__)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "engine_#{Process.pid}_#{SecureRandom.hex(4)}.en.yml")
    File.write(path, contents)
    yield path
  ensure
    FileUtils.rm_f(path) if path
  end

  def with_shipped_english_registrations(paths)
    translation = RecordingStudio::Translation
    previous = translation.instance_variable_get(:@registered_shipped_english_paths)
    translation.instance_variable_set(:@registered_shipped_english_paths, paths.dup)
    translation.reset_shipped_english!
    yield
  ensure
    translation.instance_variable_set(:@registered_shipped_english_paths, previous)
    translation.reset_shipped_english!
    translation.shipped_english
  end

  def assert_malformed_registered_shipped_english_skipped(tree, absent_key)
    with_registered_shipped_english_fixture(tree) do |path|
      with_shipped_english_registrations([]) do
        assert_nothing_raised do
          RecordingStudio::Translation.register_shipped_english(path)
          table = RecordingStudio::Translation.shipped_english
          assert_equal "Back", table.fetch("recording_studio.core.navigation.back")
          refute table.key?(absent_key)
        end
      end
    end
  end
end

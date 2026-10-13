# frozen_string_literal: true

require "test_helper"
require "yaml"

class LocalesTest < ActiveSupport::TestCase
  NAVIGATION_KEYS = {
    "back" => "Back",
    "go_back" => "Go back",
    "close" => "Close",
    "page" => "Page navigation",
    "action_page" => "Action page navigation"
  }.freeze

  LABEL_KEYS = {
    "empty" => "—"
  }.freeze

  test "engine ships only english locale files" do
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml"], files.sort
  end

  test "rails i18n load path includes the gem english locale file" do
    locale_path = File.join(engine_locales_dir, "en.yml")

    assert_includes I18n.load_path.map { |path| File.expand_path(path) }, File.expand_path(locale_path)
  end

  test "lib sources do not append i18n load path" do
    lib_dir = File.expand_path("../lib", __dir__)
    ruby_files = Dir[File.join(lib_dir, "**", "*.rb")]

    refute_empty ruby_files, "expected lib/**/*.rb files to scan"

    ruby_files.each do |path|
      source = File.read(path)

      refute_includes source, "i18n.load_path", "#{path} must not touch i18n.load_path"
      refute_includes source, "I18n.load_path", "#{path} must not touch I18n.load_path"
    end
  end

  test "english navigation keys resolve without missing translations" do
    I18n.with_locale(:en) do
      NAVIGATION_KEYS.each do |key, english|
        full_key = "recording_studio.core.navigation.#{key}"
        translation = I18n.t(full_key, default: nil)

        assert_equal english, translation, "#{full_key} should resolve to #{english.inspect}"
        assert_equal english, I18n.t(full_key, raise: true)
      end
    end
  end

  test "english label keys resolve without missing translations" do
    I18n.with_locale(:en) do
      LABEL_KEYS.each do |key, english|
        full_key = "recording_studio.core.labels.#{key}"
        translation = I18n.t(full_key, default: nil)

        assert_equal english, translation, "#{full_key} should resolve to #{english.inspect}"
        assert_equal english, I18n.t(full_key, raise: true)
      end
    end
  end

  test "en.yml nests keys under recording_studio.core" do
    core = locale_tree(File.join(engine_locales_dir, "en.yml"), "en")
           .fetch("recording_studio")
           .fetch("core")

    assert_equal NAVIGATION_KEYS, core.fetch("navigation").transform_keys(&:to_s)
    assert_equal LABEL_KEYS, core.fetch("labels").transform_keys(&:to_s)
  end

  # Hand-copied English `default:` strings that origin/main passed to t()/I18n.t
  # before this refactor. Replacing them with RecordingStudio.t must not change
  # English output — each former default must equal config/locales/en.yml.
  FORMER_MAIN_DEFAULTS = {
    "recording_studio.core.navigation.back" => "Back",
    "recording_studio.core.navigation.go_back" => "Go back",
    "recording_studio.core.navigation.close" => "Close",
    "recording_studio.core.navigation.page" => "Page navigation",
    "recording_studio.core.navigation.action_page" => "Action page navigation",
    "recording_studio.core.labels.empty" => "—"
  }.freeze

  test "former main default: strings equal en.yml values so the refactor does not drift" do
    core = locale_tree(File.join(engine_locales_dir, "en.yml"), "en")
           .fetch("recording_studio")
           .fetch("core")
    previous_locales = I18n.available_locales
    I18n.available_locales = (previous_locales + %i[en fr]).uniq

    FORMER_MAIN_DEFAULTS.each do |full_key, former_default|
      *_, group, key = full_key.split(".")
      yml_value = core.fetch(group).fetch(key)

      assert_equal former_default, yml_value,
                   "#{full_key}: former main default: #{former_default.inspect} must equal en.yml"

      I18n.with_locale(:en) do
        assert_equal former_default, RecordingStudio.t(full_key)
      end

      I18n.with_locale(:fr) do
        refute I18n.exists?(full_key, :fr)
        assert_equal former_default, RecordingStudio.t(full_key),
                     "#{full_key}: fr-without-file fallback must match former main default:"
      end
    end
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  test "gem call sites no longer hand-copy English default: on recording_studio keys" do
    roots = [
      File.expand_path("../app", __dir__),
      File.expand_path("../lib", __dir__)
    ]
    files = roots.flat_map { |root| Dir[File.join(root, "**", "*.{rb,erb}")] }
    refute_empty files

    offenders = files.filter_map do |path|
      source = File.read(path)
      next unless source.match?(/recording_studio\.[a-z_.]+/)
      next unless source.match?(/default:\s*["']|default:\s*[A-Z_]+/)

      # Allow the EMPTY_LABEL constant definition itself; forbid using it as I18n default.
      if source.include?('I18n.t("recording_studio.core.labels.empty", default: EMPTY_LABEL)') ||
         source.match?(/t\(\s*["']recording_studio\.[^"']+["']\s*,\s*default:\s*["']/)
        path
      end
    end

    assert_empty offenders,
                 "expected no hand-copied English default: on gem recording_studio lookups; found: #{offenders.join(', ')}"
  end

  test "gemspec does not depend on internationalization" do
    gemspec = File.read(File.expand_path("../recording_studio.gemspec", __dir__))

    refute_includes gemspec, "recording_studio_internationalization"
    refute_includes gemspec, "RecordingStudio_Internationalization"
  end

  test "dummy gemfile does not depend on internationalization" do
    gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    refute_includes gemfile, "recording_studio_internationalization"
    refute_includes gemfile, "RecordingStudio_Internationalization"
  end

  private

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def locale_tree(path, locale)
    YAML.safe_load_file(path, aliases: true).fetch(locale)
  end
end

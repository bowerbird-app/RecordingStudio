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

  test "engine ships only english locale files" do
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml"], files.sort
  end

  test "rails i18n load path includes the gem english locale file" do
    locale_path = File.join(engine_locales_dir, "en.yml")

    assert_includes I18n.load_path.map { |path| File.expand_path(path) }, File.expand_path(locale_path)
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

  test "en.yml nests keys under recording_studio.core" do
    tree = locale_tree(File.join(engine_locales_dir, "en.yml"), "en")
           .fetch("recording_studio")
           .fetch("core")
           .fetch("navigation")

    assert_equal NAVIGATION_KEYS, tree.transform_keys(&:to_s)
  end

  private

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def locale_tree(path, locale)
    YAML.safe_load_file(path, aliases: true).fetch(locale)
  end
end

# frozen_string_literal: true

require "test_helper"

# Proves a host nested `recording_studio.core.*` override wins over gem English
# on a real page and at the Labels call site. The YAML lives outside
# config/locales so the default dummy UI keeps gem English.
class CoreI18nHostOverrideTest < ActionDispatch::IntegrationTest
  HOST_OVERRIDE_LOCALE = File.expand_path(
    "../locales/core_host_override.en.yml",
    __dir__
  ).freeze

  setup do
    @original_load_path = I18n.load_path.dup
    @user = create_user(name: "Core I18n Host Override User")
    sign_in_as(@user)
  end

  teardown do
    restore_i18n_load_path!
    assert_equal @original_load_path, I18n.load_path,
                 "tests must not leave I18n.load_path modified"
  end

  test "host locale file overrides gem english on layout demo and labels" do
    assert File.exist?(HOST_OVERRIDE_LOCALE), "expected test-only host override at #{HOST_OVERRIDE_LOCALE}"
    refute_includes File.expand_path(HOST_OVERRIDE_LOCALE), "/config/locales/"

    assert_equal "Go back", I18n.t("recording_studio.core.navigation.go_back"),
                 "default dummy UI must keep gem English before the override is loaded"
    assert_equal "—", RecordingStudio::Labels.name_for(nil)

    I18n.load_path << HOST_OVERRIDE_LOCALE
    I18n.reload!

    assert_equal "HOST Go back", I18n.t("recording_studio.core.navigation.go_back")
    assert_equal "HOST —", RecordingStudio::Labels.name_for(nil)
    assert_equal "HOST —", RecordingStudio::Labels.empty_label

    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_includes response.body, "HOST Go back"
    refute_match(/(?<!HOST )Go back/, response.body)
  ensure
    restore_i18n_load_path!
  end

  test "without the test-only override the gem english still renders" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_includes response.body, "Go back"
    refute_includes response.body, "HOST Go back"
    assert_equal "—", RecordingStudio::Labels.name_for(nil)
    assert_equal @original_load_path, I18n.load_path
  end

  private

  def restore_i18n_load_path!
    return unless defined?(@original_load_path) && @original_load_path

    I18n.load_path.replace(@original_load_path)
    I18n.reload!
  end
end

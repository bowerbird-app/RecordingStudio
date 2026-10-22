# frozen_string_literal: true

require "test_helper"

# Proves a host nested `recording_studio.core.*` override wins at the Labels
# call site. The default layout reads Flatpack copy for back and close, so a
# host override of `recording_studio.core.navigation.back` does not change
# the page nav. The YAML lives outside
# config/locales so the default dummy UI keeps gem English; the test applies it
# through the I18n backend (no runtime load_path append).
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
    I18n.reload!
    assert_equal @original_load_path, I18n.load_path,
                 "tests must not leave I18n.load_path modified"
  end

  test "host locale file overrides labels and does not replace Flatpack nav copy" do
    assert File.exist?(HOST_OVERRIDE_LOCALE), "expected test-only host override at #{HOST_OVERRIDE_LOCALE}"
    refute_includes File.expand_path(HOST_OVERRIDE_LOCALE), "/config/locales/"

    assert_equal "Back", I18n.t("recording_studio.core.navigation.back"),
                 "default dummy UI must keep gem English before the override is applied"
    assert_equal "—", RecordingStudio::Labels.name_for(nil)

    apply_host_english_override!

    assert_equal @original_load_path, I18n.load_path,
                 "host override must not append I18n.load_path"
    assert_equal "HOST Back", I18n.t("recording_studio.core.navigation.back")
    assert_equal "HOST —", RecordingStudio::Labels.name_for(nil)
    assert_equal "HOST —", RecordingStudio::Labels.empty_label

    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_includes response.body, "Go back"
    assert_includes response.body, "Close demo"
    refute_includes response.body, "HOST Back"
  ensure
    I18n.reload!
  end

  test "without the test-only override the gem english still renders" do
    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_includes response.body, "Go back"
    refute_includes response.body, "HOST Back"
    assert_equal "—", RecordingStudio::Labels.name_for(nil)
    assert_equal @original_load_path, I18n.load_path
  end

  private

  def apply_host_english_override!
    tree = YAML.safe_load_file(HOST_OVERRIDE_LOCALE, aliases: true)
    I18n.backend.store_translations(:en, tree.fetch("en"))
  end
end

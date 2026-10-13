# frozen_string_literal: true

require "test_helper"

# Host French overrides win over the gem English fallback on real renders.
class CoreI18nFrenchHostOverrideTest < ActionDispatch::IntegrationTest
  HOST_OVERRIDE_LOCALE = File.expand_path(
    "../locales/core_host_override.fr.yml",
    __dir__
  ).freeze

  setup do
    @original_load_path = I18n.load_path.dup
    @previous_locales = I18n.available_locales
    I18n.available_locales = (@previous_locales + %i[en fr]).uniq
    @user = create_user(name: "Core I18n French Host Override User")
    sign_in_as(@user)
  end

  teardown do
    restore_i18n_load_path!
    I18n.locale = I18n.default_locale
    I18n.available_locales = @previous_locales if @previous_locales
    assert_equal @original_load_path, I18n.load_path,
                 "tests must not leave I18n.load_path modified"
  end

  test "host french locale file wins over gem english fallback on layout and labels" do
    assert File.exist?(HOST_OVERRIDE_LOCALE), "expected test-only host override at #{HOST_OVERRIDE_LOCALE}"
    refute_includes File.expand_path(HOST_OVERRIDE_LOCALE), "/config/locales/"

    I18n.t("recording_studio.core.navigation.go_back")

    I18n.load_path << HOST_OVERRIDE_LOCALE
    I18n.reload!

    I18n.with_locale(:fr) do
      assert_equal "HOST Retour", I18n.t("recording_studio.core.navigation.go_back")
      assert_equal "HOST VIDE", RecordingStudio::Labels.empty_label

      get layout_demo_path, headers: modern_headers

      assert_response :success
      assert_includes response.body, "HOST Retour"
      refute_match(/(?<!HOST )Go back/, response.body)
      refute_match(/translation missing/i, response.body)

      get action_layout_demo_path, headers: modern_headers

      assert_response :success
      assert_includes response.body, "HOST Retour court"
      assert_select "nav[aria-label='HOST Action page navigation FR']", count: 1
    end
  ensure
    restore_i18n_load_path!
  end

  private

  def restore_i18n_load_path!
    return unless defined?(@original_load_path) && @original_load_path

    I18n.load_path.replace(@original_load_path)
    I18n.reload!
  end
end

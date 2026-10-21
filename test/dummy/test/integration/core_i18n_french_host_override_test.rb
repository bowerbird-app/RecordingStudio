# frozen_string_literal: true

require "test_helper"

# Host French overrides win over the gem English fallback on real renders.
# Fixture is boot-loaded from config/locales/zz_core_host_override.fr.yml.
class CoreI18nFrenchHostOverrideTest < ActionDispatch::IntegrationTest
  HOST_OVERRIDE_LOCALE = Rails.root.join("config/locales/zz_core_host_override.fr.yml").to_s.freeze

  setup do
    @previous_locales = I18n.available_locales
    I18n.available_locales = (@previous_locales + %i[en fr]).uniq
    @user = create_user(name: "Core I18n French Host Override User")
    sign_in_as(@user)
  end

  teardown do
    I18n.locale = I18n.default_locale
    I18n.available_locales = @previous_locales if @previous_locales
  end

  test "boot-loaded host french locale file wins over gem english fallback on layout and labels" do
    assert_boot_loaded_french_override_preconditions!

    I18n.with_locale(:fr) do
      assert_equal "HOST Retour", I18n.t("recording_studio.core.navigation.go_back")
      assert_equal "HOST VIDE", RecordingStudio::Labels.empty_label

      get layout_demo_path, headers: modern_headers

      assert_response :success
      assert_includes response.body, "HOST Retour"
      refute_match(/(?<!HOST )Go back/, response.body)
      refute_match(/translation missing/i, response.body)
    end
  end

  test "boot-loaded host french Close renders on pure HTML chrome defaults page" do
    assert_boot_loaded_french_override_preconditions!
    assert I18n.exists?("recording_studio.core.navigation.close", :fr)

    page_nav_component = FlatPack::PageNav::Component
    button_component = FlatPack::Button::Component
    FlatPack::PageNav.send(:remove_const, :Component)
    FlatPack::Button.send(:remove_const, :Component)

    I18n.with_locale(:fr) do
      get layout_demo_chrome_defaults_path, headers: modern_headers

      assert_response :success
      assert_includes response.body, "HOST Fermer"
      refute_match(/(?<!HOST )Close/, response.body)
      refute_match(/translation missing/i, response.body)
    end
  ensure
    FlatPack::PageNav.const_set(:Component, page_nav_component) if page_nav_component
    FlatPack::Button.const_set(:Component, button_component) if button_component
  end

  private

  def assert_boot_loaded_french_override_preconditions!
    assert File.exist?(HOST_OVERRIDE_LOCALE), "expected boot-loaded host override at #{HOST_OVERRIDE_LOCALE}"
    assert_includes File.expand_path(HOST_OVERRIDE_LOCALE), "/config/locales/"

    load_path = I18n.load_path.map { |path| File.expand_path(path) }
    gem_en = File.expand_path(RecordingStudio::Engine.root.join("config/locales/en.yml"))
    host_fr = File.expand_path(HOST_OVERRIDE_LOCALE)

    assert_includes load_path, gem_en
    assert_includes load_path, host_fr
    assert_operator load_path.index(gem_en), :<, load_path.index(host_fr),
                    "gem en.yml must load before host fr override"

    assert I18n.exists?("recording_studio.core.navigation.go_back", :fr)
    assert I18n.exists?("recording_studio.core.navigation.back", :fr)
    assert I18n.exists?("recording_studio.core.navigation.action_page", :fr)
    assert I18n.exists?("recording_studio.core.labels.empty", :fr)
  end
end

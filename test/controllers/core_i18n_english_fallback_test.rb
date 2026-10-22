# frozen_string_literal: true

require "test_helper"

# Behavioral renders: a locale without translations shows loaded English for
# every translated call-site group (default layout, page_nav, Labels).
# Uses :de so boot-loaded host :fr overrides do not interfere.
class CoreI18nEnglishFallbackTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Core I18n Fallback User")
    sign_in_as(@user)
    @previous_locales = I18n.available_locales
    I18n.available_locales = (@previous_locales + %i[en de fr]).uniq
  end

  teardown do
    I18n.locale = I18n.default_locale
    I18n.available_locales = @previous_locales if @previous_locales
  end

  test "missing locale without translations renders gem english on default layout" do
    I18n.with_locale(:de) do
      refute I18n.exists?("recording_studio.core.navigation.back", :de)

      get layout_demo_path, headers: modern_headers

      assert_response :success
      assert_includes @response.body, "Go back"
      assert_includes @response.body, "Close demo"
      refute_match(/translation missing/i, @response.body)
      refute_includes @response.body, "Translation missing"
    end
  end

  test "missing locale without translations resolves Labels empty marker to gem english" do
    I18n.with_locale(:de) do
      refute I18n.exists?("recording_studio.core.labels.empty", :de)
      assert_equal "—", RecordingStudio::Labels.empty_label
      assert_equal "—", RecordingStudio::Labels.name_for(nil)
    end
  end

  test "english render matches gem english strings from main" do
    I18n.with_locale(:en) do
      get layout_demo_path, headers: modern_headers
      assert_response :success
      english_layout = @response.body.dup

      assert_includes english_layout, "Go back"
      assert_includes english_layout, "Close demo"
      refute_match(/translation missing/i, english_layout)
      assert_equal "—", RecordingStudio::Labels.empty_label
    end
  end
end

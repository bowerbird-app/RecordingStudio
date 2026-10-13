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
      refute I18n.exists?("recording_studio.core.navigation.go_back", :de)

      get layout_demo_path, headers: modern_headers

      assert_response :success
      assert_includes @response.body, "Go back"
      assert_includes @response.body, "Close demo"
      refute_match(/translation missing/i, @response.body)
      refute_includes @response.body, "Translation missing"
    end
  end

  test "missing locale without translations renders gem english on non-FlatPack page nav fallback" do
    page_nav_component = FlatPack::PageNav::Component
    FlatPack::PageNav.send(:remove_const, :Component)

    I18n.with_locale(:de) do
      get layout_demo_path, headers: modern_headers

      assert_response :success
      assert_select "nav[aria-label='Page navigation']", count: 1
      assert_includes @response.body, 'aria-label="Go back"'
      refute_match(/translation missing/i, @response.body)
    end
  ensure
    FlatPack::PageNav.const_set(:Component, page_nav_component) if page_nav_component
  end

  test "missing locale without translations renders gem english Close on pure HTML fallback" do
    page_nav_component = FlatPack::PageNav::Component
    button_component = FlatPack::Button::Component
    FlatPack::PageNav.send(:remove_const, :Component)
    FlatPack::Button.send(:remove_const, :Component)

    I18n.with_locale(:de) do
      get layout_demo_chrome_defaults_path, headers: modern_headers

      assert_response :success
      assert_includes @response.body, "Go back"
      assert_includes @response.body, "Close"
      refute_match(/translation missing/i, @response.body)
    end
  ensure
    FlatPack::PageNav.const_set(:Component, page_nav_component) if page_nav_component
    FlatPack::Button.const_set(:Component, button_component) if button_component
  end

  test "missing locale without translations renders gem english on action page nav" do
    I18n.with_locale(:de) do
      get action_layout_demo_path, headers: modern_headers

      assert_response :success
      assert_select "nav[aria-label='Action page navigation']", count: 1
      assert_includes @response.body, "Back"
      refute_match(/translation missing/i, @response.body)
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

      get action_layout_demo_path, headers: modern_headers
      assert_response :success
      english_action = @response.body.dup

      assert_includes english_layout, "Go back"
      assert_includes english_layout, "Close demo"
      assert_includes english_action, "Back"
      assert_includes english_action, "Action page navigation"
      refute_match(/translation missing/i, english_layout)
      refute_match(/translation missing/i, english_action)
      assert_equal "—", RecordingStudio::Labels.empty_label
    end
  end

  test "deleted english key on action layout demo returns 200 not 500" do
    I18n.backend.store_translations(:en, {
                                      recording_studio: { core: { navigation: { back: nil } } }
                                    })
    I18n.backend.store_translations(:fr, {
                                      recording_studio: { core: { navigation: { back: nil } } }
                                    })

    refute I18n.exists?("recording_studio.core.navigation.back", :en)
    refute I18n.exists?("recording_studio.core.navigation.back", :fr)

    I18n.with_locale(:fr) do
      get action_layout_demo_path, headers: modern_headers

      assert_response :success
      refute_equal 500, @response.status
    end
  ensure
    I18n.reload!
  end
end

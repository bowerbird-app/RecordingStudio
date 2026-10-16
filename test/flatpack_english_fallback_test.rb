# frozen_string_literal: true

require "test_helper"

class FlatpackEnglishFallbackTest < ActiveSupport::TestCase
  setup do
    @previous_locales = I18n.available_locales
    I18n.available_locales = (@previous_locales + %i[en de]).uniq
    RecordingStudio::FlatpackEnglishFallback.install!
  end

  teardown do
    I18n.locale = I18n.default_locale
    I18n.available_locales = @previous_locales if @previous_locales
    I18n.reload!
  end

  test "missing flatpack key in another locale uses loaded english" do
    I18n.with_locale(:de) do
      refute I18n.exists?("flatpack.page_nav.label", :de)
      refute I18n.exists?("flatpack.top_nav.more", :de)

      assert_equal "Page navigation", I18n.t("flatpack.page_nav.label")
      assert_equal "More navigation items", I18n.t("flatpack.top_nav.more")
    end
  end

  test "a translated flatpack key in the active locale stays" do
    I18n.backend.store_translations(:de, flatpack: { page_nav: { label: "Seitennavigation" } })

    I18n.with_locale(:de) do
      assert_equal "Seitennavigation", I18n.t("flatpack.page_nav.label")
    end
  end

  test "a missing key outside flatpack still reports translation missing" do
    I18n.with_locale(:de) do
      message = I18n.t("not_a_flatpack_key")

      assert_match(/translation missing/i, message)
    end
  end

  test "install keeps the same handler when called twice" do
    handler = I18n.exception_handler
    RecordingStudio::FlatpackEnglishFallback.install!

    assert_same handler, I18n.exception_handler
  end
end

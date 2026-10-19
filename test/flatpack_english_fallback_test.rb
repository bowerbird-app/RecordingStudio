# frozen_string_literal: true

require "test_helper"

class FlatpackEnglishFallbackTest < ActiveSupport::TestCase
  setup do
    @previous_locales = I18n.available_locales
    I18n.available_locales = (@previous_locales + %i[en de]).uniq
  end

  teardown do
    I18n.locale = I18n.default_locale
    I18n.available_locales = @previous_locales if @previous_locales
  end

  test "missing flatpack key in a non-english locale returns the english string" do
    I18n.with_locale(:de) do
      refute I18n.exists?("flatpack.page_nav.label", :de)

      assert_equal "Page navigation", FlatPack::Copy.t("page_nav.label")
    end
  end

  test "raise_on_missing_translations still raises for a non-flatpack key" do
    with_raise_on_missing_translations do
      I18n.with_locale(:de) do
        error = assert_raises(I18n::MissingTranslationData) { I18n.t("not_a_flatpack_key") }

        assert_match(/not_a_flatpack_key/, error.message)
        assert_equal "Page navigation", FlatPack::Copy.t("page_nav.label")
      end
    end
  end

  private

  # Same gate as I18n::Railtie: raise_on_missing_translations replaces only
  # the default exception handler. A custom handler would leave this raise off.
  def with_raise_on_missing_translations
    previous_handler = I18n.exception_handler
    previous_raise = Rails.application.config.i18n.raise_on_missing_translations
    previous_view_raise = ActionView::Helpers::TranslationHelper.raise_on_missing_translations

    Rails.application.config.i18n.raise_on_missing_translations = true
    ActionView::Helpers::TranslationHelper.raise_on_missing_translations = true
    if I18n.exception_handler.is_a?(I18n::ExceptionHandler)
      I18n.exception_handler = lambda { |exception, *|
        exception = exception.to_exception if exception.is_a?(I18n::MissingTranslation)
        raise exception
      }
    end

    yield
  ensure
    I18n.exception_handler = previous_handler
    Rails.application.config.i18n.raise_on_missing_translations = previous_raise
    ActionView::Helpers::TranslationHelper.raise_on_missing_translations = previous_view_raise
  end
end

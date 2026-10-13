# frozen_string_literal: true

require "test_helper"

class LabelsI18nTest < ActiveSupport::TestCase
  test "EMPTY_LABEL constant remains the english em dash" do
    assert_equal "—", RecordingStudio::Labels::EMPTY_LABEL
  end

  test "empty label helpers return literal english at the call site" do
    I18n.with_locale(:en) do
      assert_equal "—", RecordingStudio::Labels.empty_label
      assert_equal "—", RecordingStudio::Labels.name_for(nil)
      assert_equal "—", RecordingStudio::Labels.label_for(nil)
      assert_equal "—", RecordingStudio::Labels.type_label_for(nil)
      assert_equal "—", RecordingStudio::Labels.type_label_for("")
      assert_equal "—", RecordingStudio::Labels.type_plural_label_for(nil)
      assert_equal "—", RecordingStudio::Labels.type_plural_label_for("")
      assert_equal "—", RecordingStudio::Labels.title_for(nil)
    end
  end

  test "empty label resolution honors I18n.locale per call and is not memoized" do
    previous_locales = I18n.available_locales
    I18n.available_locales = (previous_locales + %i[en fr]).uniq
    store_empty_label_translation(:fr, "VIDE")

    assert_english_empty_labels
    assert_french_empty_labels
    assert_english_empty_labels
  ensure
    store_empty_label_translation(:fr, nil)
    I18n.available_locales = previous_locales if previous_locales
    I18n.reload!
  end

  test "empty_label falls back to english default when key is absent" do
    previous_locales = I18n.available_locales
    I18n.available_locales = (previous_locales + %i[en xx]).uniq

    I18n.with_locale(:xx) do
      assert_equal "—", RecordingStudio::Labels.empty_label
      assert_equal "—", RecordingStudio::Labels.name_for(nil)
    end
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  private

  def store_empty_label_translation(locale, value)
    # Force backend init before store so a later lazy reload from load_path
    # (including boot-loaded zz_core_host_override.fr.yml) cannot clobber this.
    I18n.exists?("recording_studio.core.labels.empty", locale)
    I18n.backend.store_translations(locale, {
                                      recording_studio: { core: { labels: { empty: value } } }
                                    })
  end

  def assert_english_empty_labels
    I18n.with_locale(:en) do
      assert_equal "—", RecordingStudio::Labels.name_for(nil)
      assert_equal "—", RecordingStudio::Labels.type_label_for(nil)
      assert_equal "—", RecordingStudio::Labels.title_for(nil)
      assert_equal "—", RecordingStudio::Labels.empty_label
    end
  end

  def assert_french_empty_labels
    I18n.with_locale(:fr) do
      assert_equal "VIDE", RecordingStudio::Labels.name_for(nil)
      assert_equal "VIDE", RecordingStudio::Labels.type_label_for(nil)
      assert_equal "VIDE", RecordingStudio::Labels.title_for(nil)
      assert_equal "VIDE", RecordingStudio::Labels.empty_label
    end
  end
end

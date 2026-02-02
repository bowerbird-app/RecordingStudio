# frozen_string_literal: true

require "test_helper"

class RecordableTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = ["Page"]
    RecordingStudio::DelegatedTypeRegistrar.apply!
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_readonly_returns_true_for_persisted_record
    page = Page.create!(title: "Hello")

    assert page.readonly?
  end

  def test_update_raises_readonly_error
    page = Page.create!(title: "Hello")

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      page.update!(title: "Updated")
    end
  end

  def test_destroy_raises_readonly_error
    page = Page.create!(title: "Hello")

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      page.destroy
    end
  end
end

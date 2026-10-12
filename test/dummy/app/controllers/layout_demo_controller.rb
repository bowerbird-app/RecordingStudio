class LayoutDemoController < ApplicationController
  include RecordingStudio::UsesDefaultLayout

  def show
  end

  # Anchor URL only — exercises layout default Close copy when PageNav/Button are absent.
  def chrome_defaults
  end
end

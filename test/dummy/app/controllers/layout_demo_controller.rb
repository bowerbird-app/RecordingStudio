class LayoutDemoController < ApplicationController
  recording_studio_layout

  def show
  end

  # Anchor URL only — exercises layout default Close copy when PageNav/Button are absent.
  def chrome_defaults
  end

  def contract
    flash.now[:notice] = "Saved the page"
    flash.now[:alert] = "Could not save the page"
    render :show
  end
end

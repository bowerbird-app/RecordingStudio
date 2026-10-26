class LayoutDemoController < ApplicationController
  recording_studio_layout

  def show
  end

  # Anchor only. Flatpack supplies the close label. Nothing is registered.
  def chrome_defaults
  end

  def contract
    flash.now[:notice] = "Saved the page"
    flash.now[:alert] = "Could not save the page"
    render :show
  end
end

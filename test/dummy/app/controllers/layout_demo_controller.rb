class LayoutDemoController < ApplicationController
  recording_studio_layout

  def show
  end

  # Anchor URL only — Flatpack supplies the default close tooltip.
  def chrome_defaults
  end

  # No page nav registration and no return_to. Flatpack renders no icon row.
  def plain
  end

  def contract
    flash.now[:notice] = "Saved the page"
    flash.now[:alert] = "Could not save the page"
    render :show
  end
end

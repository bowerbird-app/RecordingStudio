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

  def page_nav_right
  end

  def page_nav_content_for
  end

  def page_nav_both
  end

  def background_image
  end

  def background_content_for
  end

  def page_width_narrow
  end

  def page_width_full
  end
end

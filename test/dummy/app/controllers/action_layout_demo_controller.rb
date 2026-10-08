class ActionLayoutDemoController < ApplicationController
  layout "recording_studio/action_layout"
  helper RecordingStudio::LayoutHelper

  def show
  end
end

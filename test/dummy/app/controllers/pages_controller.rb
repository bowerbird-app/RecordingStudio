class PagesController < ApplicationController
  before_action :load_workspace
  before_action :load_recording, only: %i[show edit update destroy]

  def index
    @recordings = @workspace.recordings_of(Page).kept.recent
  end

  def show
    redirect_to recording_path(@recording)
  end

  def new
    @recordable = Page.new
  end

  def create
    recording = @workspace.record(Page, actor: current_actor, metadata: { source: "ui" }) do |page|
      page.assign_attributes(page_params)
      page.version = 1
    end

    redirect_to recording_path(recording)
  end

  def edit
    @recordable = @recording.recordable
  end

  def update
    updated_recording = @workspace.revise(@recording, actor: current_actor, metadata: { source: "ui" }) do |page|
      page.assign_attributes(page_params)
      page.version = @recording.recordable.version.to_i + 1
      page.original_id = @recording.recordable.original_id || @recording.recordable.id
    end

    redirect_to recording_path(updated_recording)
  end

  def destroy
    @workspace.unrecord(@recording, actor: current_actor, metadata: { source: "ui" })
    redirect_to pages_path
  end

  private

  def load_workspace
    @workspace = Workspace.first_or_create!(name: "Studio Workspace")
  end

  def load_recording
    @recording = @workspace.recordings.find(params[:recording_id])
  end

  def page_params
    params.require(:page).permit(:title, :summary)
  end
end

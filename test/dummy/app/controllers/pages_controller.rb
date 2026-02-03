class PagesController < ApplicationController
  before_action :load_workspace
  before_action :load_recording, only: %i[show edit update destroy restore]

  def index
    scope = @workspace.recordings_of(Page)
    @recordings = if params[:trashed].to_s == "true"
      scope.including_trashed.trashed.recent
    else
      scope.recent
    end
  end

  def show
    redirect_to recording_path(@recording)
  end

  def new
    @recordable = Page.new
  end

  def create
    recording = @workspace.record(Page, actor: current_actor, impersonator: Current.impersonator, metadata: { source: "ui" }) do |page|
      page.assign_attributes(page_params)
    end

    redirect_to recording_path(recording)
  end

  def edit
    @recordable = @recording.recordable
  end

  def update
    updated_recording = @workspace.revise(@recording, actor: current_actor, impersonator: Current.impersonator, metadata: { source: "ui" }) do |page|
      page.assign_attributes(page_params)
      page.original_id = @recording.recordable.original_id || @recording.recordable.id
    end

    redirect_to recording_path(updated_recording)
  end

  def destroy
    @workspace.trash(@recording, actor: current_actor, impersonator: Current.impersonator, metadata: { source: "ui" }, include_children: true)
    redirect_to pages_path
  end

  def restore
    @workspace.restore(@recording, actor: current_actor, impersonator: Current.impersonator, metadata: { source: "ui" }, include_children: true)
    redirect_to recording_path(@recording)
  end

  private

  def load_workspace
    @workspace = Workspace.first_or_create!(name: "Studio Workspace")
  end

  def load_recording
    @recording = @workspace.recordings.including_trashed.find(params[:recording_id])
  end

  def page_params
    params.require(:page).permit(:title, :summary)
  end
end

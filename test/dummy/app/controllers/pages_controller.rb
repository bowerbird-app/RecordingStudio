class PagesController < ApplicationController
  before_action :load_workspace
  before_action :load_root_recording
  before_action :load_recording, only: %i[show edit update destroy restore]

  def index
    scope = @root_recording.recordings_of(RecordingStudioPage)
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
    @recordable = RecordingStudioPage.new
  end

  def create
    recording = @root_recording.record(RecordingStudioPage, actor: current_actor, impersonator: Current.impersonator, metadata: { source: "ui" }) do |page|
      page.assign_attributes(page_params)
    end

    redirect_to recording_path(recording)
  end

  def edit
    @recordable = @recording.recordable
  end

  def update
    updated_recording = @root_recording.revise(@recording, actor: current_actor, impersonator: Current.impersonator, metadata: { source: "ui" }) do |page|
      page.assign_attributes(page_params)
    end

    redirect_to recording_path(updated_recording)
  end

  def destroy
    @root_recording.trash(@recording, actor: current_actor, impersonator: Current.impersonator, metadata: { source: "ui" }, include_children: true)
    redirect_to pages_path
  end

  def restore
    @root_recording.restore(@recording, actor: current_actor, impersonator: Current.impersonator, metadata: { source: "ui" }, include_children: true)
    redirect_to recording_path(@recording)
  end

  private

  def load_workspace
    @workspace = Workspace.first_or_create!(name: "Studio Workspace")
  end

  def load_root_recording
    @root_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
      recordable: @workspace,
      parent_recording_id: nil
    )
  end

  def load_recording
    @recording = RecordingStudio::Recording.for_root(@root_recording.id).including_trashed.find(params[:recording_id])
  end

  def page_params
    params.require(:page).permit(:title, :summary)
  end
end

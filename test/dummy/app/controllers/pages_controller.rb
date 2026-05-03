class PagesController < ApplicationController
  before_action :load_workspace
  before_action :load_root_recording
  before_action :load_recording, only: %i[show edit update destroy]

  def index
    @recordings = @root_recording.recordings_of(RecordingStudioPage).recent
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
    ActiveRecord::Base.transaction do
      destroy_recording_tree(@recording)
    end

    redirect_to pages_path, status: :see_other
  end

  private

  def load_workspace
    @workspace = workspace_from_recording || Workspace.order(:created_at).first_or_create!(name: "Studio Workspace")
  end

  def load_root_recording
    @root_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
      recordable: @workspace,
      parent_recording_id: nil
    )
  end

  def load_recording
    @recording = RecordingStudio::Recording.for_root(@root_recording.id).find(params[:recording_id])
  end

  def workspace_from_recording
    return if params[:recording_id].blank?

    recording = RecordingStudio::Recording.unscoped.find_by(id: params[:recording_id])
    workspace = recording&.root_recording&.recordable
    workspace if workspace.is_a?(Workspace)
  end

  def destroy_recording_tree(recording)
    recording.child_recordings.find_each do |child_recording|
      destroy_recording_tree(child_recording)
    end

    delete_recordable_snapshots(recording)
    recording.destroy!
  end

  def delete_recordable_snapshots(recording)
    snapshot_ids_by_type = Hash.new { |hash, key| hash[key] = [] }

    collect_recordable_snapshot(snapshot_ids_by_type, recording.recordable_type, recording.recordable_id)
    recording.events.each do |event|
      collect_recordable_snapshot(snapshot_ids_by_type, event.recordable_type, event.recordable_id)
      collect_recordable_snapshot(snapshot_ids_by_type, event.previous_recordable_type, event.previous_recordable_id)
    end

    snapshot_ids_by_type.each do |recordable_type, ids|
      recordable_type.constantize.where(id: ids.uniq).delete_all
    end
  end

  def collect_recordable_snapshot(snapshot_ids_by_type, recordable_type, recordable_id)
    return if recordable_type.blank? || recordable_id.blank?

    snapshot_ids_by_type[recordable_type] << recordable_id
  end

  def page_params
    params.require(:page).permit(:title, :summary)
  end
end

class WorkspacesController < ApplicationController
  def index
    root_ids = RecordingStudio::Services::AccessCheck.root_recording_ids_for(actor: current_actor)
    workspace_ids = RecordingStudio::Recording.unscoped.where(id: root_ids, recordable_type: "Workspace").pluck(:recordable_id)

    @workspaces = Workspace.where(id: workspace_ids).order(created_at: :desc)
  end

  def show
    @workspace = Workspace.find(params[:id])
    @root_recording = root_recording_for(@workspace)

    require_root_access!(@root_recording, minimum_role: :view)

    @can_edit_access = RecordingStudio::Services::AccessCheck.root_recording_ids_for(
      actor: current_actor,
      minimum_role: :admin
    ).include?(@root_recording.id)

    @access_grants = root_access_grants(@root_recording)

    @recordings = @root_recording.recordings_query(include_children: true)
      .including_trashed
      .includes(:recordable)
      .order(created_at: :asc)

    @recordings_by_parent = @recordings.group_by(&:parent_recording_id)
  end

  def new
    @workspace = Workspace.new
  end

  def create
    @workspace = Workspace.new(workspace_params)

    if @workspace.save
      ensure_root_access!(@workspace)
      redirect_to workspaces_path, notice: "Workspace created."
    else
      flash.now[:alert] = @workspace.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    workspace = Workspace.find(params[:id])
    root_recording = root_recording_for(workspace)
    root_recording&.destroy!
    workspace.destroy!

    redirect_to workspaces_path, notice: "Workspace deleted."
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name)
  end

  def root_recording_for(workspace)
    RecordingStudio::Recording.unscoped.find_by!(recordable: workspace, parent_recording_id: nil)
  end

  def ensure_root_access!(workspace)
    return if current_actor.nil?

    root_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: workspace, parent_recording_id: nil)
    role_value = RecordingStudio::Access.roles.fetch("admin")

    existing = RecordingStudio::Recording.unscoped
      .where(root_recording_id: root_recording.id, parent_recording_id: root_recording.id, recordable_type: "RecordingStudio::Access")
      .joins("INNER JOIN recording_studio_accesses ON recording_studio_accesses.id = recording_studio_recordings.recordable_id")
      .where(recording_studio_accesses: { actor_type: current_actor.class.name, actor_id: current_actor.id, role: role_value })
      .exists?

    return if existing

    access = RecordingStudio::Access.create!(actor: current_actor, role: :admin)
    RecordingStudio::Recording.create!(
      recordable: access,
      parent_recording: root_recording,
      root_recording: root_recording
    )
  end

  def root_access_grants(root)
    access_recordings = RecordingStudio::Recording.unscoped
      .where(root_recording_id: root.id, parent_recording_id: root.id, recordable_type: "RecordingStudio::Access")
      .includes(recordable: :actor)
      .order(created_at: :desc)

    best_by_actor = {}
    access_recordings.each do |recording|
      access = recording.recordable
      next unless access

      key = [access.actor_type, access.actor_id]
      current_best = best_by_actor[key]
      next if current_best && !better_access_grant?(recording, current_best)

      best_by_actor[key] = recording
    end

    best_by_actor.values.sort_by do |recording|
      access = recording.recordable
      [access&.actor&.name.to_s.downcase, access&.actor_type.to_s, access&.actor_id.to_s]
    end
  end

  def better_access_grant?(candidate_recording, existing_recording)
    candidate = candidate_recording.recordable
    existing = existing_recording.recordable
    return false unless candidate
    return true unless existing

    candidate_role_value = RecordingStudio::Access.roles.fetch(candidate.role.to_s, -1)
    existing_role_value = RecordingStudio::Access.roles.fetch(existing.role.to_s, -1)

    return true if candidate_role_value > existing_role_value
    return false if candidate_role_value < existing_role_value

    candidate.created_at.to_i > existing.created_at.to_i
  end
end

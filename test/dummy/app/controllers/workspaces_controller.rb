class WorkspacesController < ApplicationController
  def index
    workspace_ids = RecordingStudio::Services::AccessCheck.container_ids_for(
      actor: current_actor,
      container_class: Workspace
    )

    @workspaces = Workspace.where(id: workspace_ids).order(created_at: :desc)
  end

  def show
    @workspace = Workspace.find(params[:id])

    @can_edit_access = RecordingStudio::Services::AccessCheck.container_ids_for(
      actor: current_actor,
      container_class: Workspace,
      minimum_role: :admin
    ).include?(@workspace.id)

    @access_grants = container_access_grants(@workspace)

    @recordings = @workspace.recordings(include_children: true)
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
      ensure_container_access!(@workspace)
      redirect_to workspaces_path, notice: "Workspace created."
    else
      flash.now[:alert] = @workspace.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    workspace = Workspace.find(params[:id])
    workspace.destroy!

    redirect_to workspaces_path, notice: "Workspace deleted."
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name)
  end

  def ensure_container_access!(workspace)
    return if current_actor.nil?

    role_value = RecordingStudio::Access.roles.fetch("admin")

    existing = RecordingStudio::Recording
      .for_container(workspace)
      .where(parent_recording_id: nil, recordable_type: "RecordingStudio::Access")
      .joins("INNER JOIN recording_studio_accesses ON recording_studio_accesses.id = recording_studio_recordings.recordable_id")
      .where(recording_studio_accesses: { actor_type: current_actor.class.name, actor_id: current_actor.id, role: role_value })
      .exists?

    return if existing

    access = RecordingStudio::Access.create!(actor: current_actor, role: :admin)
    RecordingStudio::Recording.create!(
      container: workspace,
      recordable: access,
      parent_recording: nil
    )
  end

  def container_access_grants(container)
    access_recordings = RecordingStudio::Recording
      .for_container(container)
      .where(parent_recording_id: nil, recordable_type: "RecordingStudio::Access")
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

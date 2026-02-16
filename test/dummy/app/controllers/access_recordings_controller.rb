class AccessRecordingsController < ApplicationController
  before_action :set_return_to
  before_action :set_access_recording, only: [ :edit, :update ]
  before_action :authorize_edit_access!, only: [ :edit, :update ]

  before_action :set_access_context, only: [ :new, :create ]
  before_action :authorize_create_access!, only: [ :new, :create ]

  helper_method :access_actor_options

  def new
    @access = RecordingStudio::Access.new(role: "view")
  end

  def create
    access_attributes = params.require(:access)
    role = access_attributes[:role].to_s

    unless RecordingStudio::Access.roles.key?(role)
      @access = RecordingStudio::Access.new(role: role)
      flash.now[:alert] = "Role is invalid."
      return render :new, status: :unprocessable_entity
    end

    actor = actor_from_key(access_attributes[:actor_key])

    unless actor.is_a?(User) || actor.is_a?(SystemActor)
      @access = RecordingStudio::Access.new(role: role)
      flash.now[:alert] = "Actor is invalid."
      return render :new, status: :unprocessable_entity
    end

    if access_exists_for_actor?(actor)
      @access = RecordingStudio::Access.new(actor: actor, role: role)
      flash.now[:alert] = "Actor already has access."
      return render :new, status: :unprocessable_entity
    end

    @root_recording.record(RecordingStudio::Access, actor: current_actor, parent_recording: @parent_recording) do |access|
      access.actor = actor
      access.role = role
    end

    redirect_to(@return_to || default_return_path, notice: "Access added.")
  end

  def edit
    @access = @access_recording.recordable
  end

  def update
    role = params.require(:access)[:role].to_s

    unless RecordingStudio::Access.roles.key?(role)
      @access = @access_recording.recordable
      flash.now[:alert] = "Role is invalid."
      return render :edit, status: :unprocessable_entity
    end

    @access_recording.root_recording.revise(@access_recording, actor: current_actor) do |access|
      access.role = role
    end

    redirect_to(@return_to || workspace_path(@access_recording.root_recording.recordable), notice: "Access updated.")
  end

  private

  def set_access_context
    if params[:parent_recording_id].present?
      @parent_recording = RecordingStudio::Recording.includes(:root_recording, recordable: :actor).find(params[:parent_recording_id])
      @root_recording = @parent_recording.root_recording
    else
      @root_recording = RecordingStudio::Recording.includes(:recordable).find(params[:root_recording_id])
      @parent_recording = nil
    end
  end

  def default_return_path
    if @parent_recording
      recording_path(@parent_recording)
    else
      workspace_path(@root_recording.recordable)
    end
  end

  def access_actor_options
    users = User.order(:name).map { |user| [ "#{user.name} (User)", "User:#{user.id}" ] }
    system_actors = SystemActor.order(:name).map { |system_actor| [ "#{system_actor.name} (System)", "SystemActor:#{system_actor.id}" ] }
    options = users
    options += system_actors if system_actors.any?
    options
  end

  def set_access_recording
    @access_recording = RecordingStudio::Recording
      .includes(:root_recording, recordable: :actor, parent_recording: :recordable)
      .find(params[:id])

    return if @access_recording.recordable_type == "RecordingStudio::Access"

    raise ActiveRecord::RecordNotFound
  end

  def set_return_to
    @return_to = safe_return_to
  end

  def safe_return_to
    candidate = params[:return_to].presence || request.referer
    return if candidate.blank?

    uri = URI.parse(candidate)
    path = uri.path.to_s
    path += "?#{uri.query}" if uri.query.present?

    return if path.blank?
    return if !path.start_with?("/") || path.start_with?("//")

    path
  rescue URI::InvalidURIError
    nil
  end

  def authorize_create_access!
    if @parent_recording.nil?
      allowed_root_ids = RecordingStudio::Services::AccessCheck.root_recording_ids_for(
        actor: current_actor,
        minimum_role: :admin
      )

      return if allowed_root_ids.include?(@root_recording.id)
    else
      return if RecordingStudio::Services::AccessCheck.allowed?(
        actor: current_actor,
        recording: @parent_recording,
        role: :admin
      )
    end

    redirect_to(@return_to || default_return_path, alert: "You are not authorized to add access.")
  end

  def authorize_edit_access!
    if @access_recording.parent_recording_id == @access_recording.root_recording_id
      allowed_root_ids = RecordingStudio::Services::AccessCheck.root_recording_ids_for(
        actor: current_actor,
        minimum_role: :admin
      )

      return if allowed_root_ids.include?(@access_recording.root_recording_id)
    else
      return if RecordingStudio::Services::AccessCheck.allowed?(
        actor: current_actor,
        recording: @access_recording.parent_recording,
        role: :admin
      )
    end

    redirect_to(safe_return_to || workspace_path(@access_recording.root_recording.recordable),
                alert: "You are not authorized to edit access.")
  end

  def access_exists_for_actor?(actor)
    parent_id = @parent_recording&.id || @root_recording.id

    RecordingStudio::Recording
      .joins("INNER JOIN recording_studio_accesses ON recording_studio_accesses.id = recording_studio_recordings.recordable_id")
      .where(recordable_type: "RecordingStudio::Access", root_recording_id: @root_recording.id,
             parent_recording_id: parent_id)
      .where(recording_studio_accesses: { actor_type: actor.class.name, actor_id: actor.id })
      .exists?
  end
end

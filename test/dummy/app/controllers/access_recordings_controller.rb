class AccessRecordingsController < ApplicationController
  before_action :set_return_to
  before_action :set_access_recording, only: [:edit, :update]
  before_action :authorize_edit_access!, only: [:edit, :update]

  before_action :set_access_context, only: [:new, :create]
  before_action :authorize_create_access!, only: [:new, :create]

  helper_method :access_actor_options

  def new
    @access = RecordingStudio::Access.new(role: "view")
  end

  def create
    role = access_params[:role].to_s

    unless RecordingStudio::Access.roles.key?(role)
      @access = RecordingStudio::Access.new(role: role)
      flash.now[:alert] = "Role is invalid."
      return render :new, status: :unprocessable_entity
    end

    actor = actor_from_key(access_params[:actor_key])

    unless actor.is_a?(User) || actor.is_a?(SystemActor)
      @access = RecordingStudio::Access.new(role: role)
      flash.now[:alert] = "Actor is invalid."
      return render :new, status: :unprocessable_entity
    end

    @container.record(RecordingStudio::Access, actor: current_actor, parent_recording: @parent_recording) do |access|
      access.actor = actor
      access.role = role
    end

    redirect_to(@return_to || default_return_path, notice: "Access added.")
  end

  def edit
    @access = @access_recording.recordable
  end

  def update
    role = access_params[:role].to_s

    unless RecordingStudio::Access.roles.key?(role)
      @access = @access_recording.recordable
      flash.now[:alert] = "Role is invalid."
      return render :edit, status: :unprocessable_entity
    end

    @access_recording.container.revise(@access_recording, actor: current_actor) do |access|
      access.role = role
    end

    redirect_to(@return_to || workspace_path(@access_recording.container), notice: "Access updated.")
  end

  private

  def set_access_context
    if params[:parent_recording_id].present?
      @parent_recording = RecordingStudio::Recording.includes(:container, recordable: :actor).find(params[:parent_recording_id])
      @container = @parent_recording.container
    else
      container_type = params[:container_type].to_s
      container_id = params[:container_id]
      raise ActiveRecord::RecordNotFound if container_type.blank? || container_id.blank?

      @container = container_type.constantize.find(container_id)
      @parent_recording = nil
    end
  rescue NameError
    raise ActiveRecord::RecordNotFound
  end

  def default_return_path
    if @parent_recording
      recording_path(@parent_recording)
    else
      workspace_path(@container)
    end
  end

  def access_actor_options
    users = User.order(:name).map { |user| ["#{user.name} (User)", "User:#{user.id}"] }
    system_actors = SystemActor.order(:name).map { |system_actor| ["#{system_actor.name} (System)", "SystemActor:#{system_actor.id}"] }
    options = users
    options += system_actors if system_actors.any?
    options
  end

  def set_access_recording
    @access_recording = RecordingStudio::Recording
      .includes(recordable: :actor, parent_recording: :recordable)
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

  def access_params
    params.require(:access).permit(:role, :actor_key)
  end

  def authorize_create_access!
    if @parent_recording.nil?
      allowed_container_ids = RecordingStudio::Services::AccessCheck.container_ids_for(
        actor: current_actor,
        container_class: @container.class,
        minimum_role: :admin
      )

      return if allowed_container_ids.include?(@container.id)
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
    if @access_recording.parent_recording_id.nil?
      allowed_container_ids = RecordingStudio::Services::AccessCheck.container_ids_for(
        actor: current_actor,
        container_class: @access_recording.container.class,
        minimum_role: :admin
      )

      return if allowed_container_ids.include?(@access_recording.container_id)
    else
      return if RecordingStudio::Services::AccessCheck.allowed?(
        actor: current_actor,
        recording: @access_recording.parent_recording,
        role: :admin
      )
    end

    redirect_to(safe_return_to || workspace_path(@access_recording.container), alert: "You are not authorized to edit access.")
  end
end

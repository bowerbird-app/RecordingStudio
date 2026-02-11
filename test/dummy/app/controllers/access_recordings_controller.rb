class AccessRecordingsController < ApplicationController
  before_action :set_access_recording
  before_action :authorize_edit_access!
  before_action :set_return_to

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
    params.require(:access).permit(:role)
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

class BoundaryRecordingsController < ApplicationController
  before_action :set_return_to

  before_action :set_parent_recording, only: [ :new, :create ]
  before_action :authorize_manage_parent_boundary!, only: [ :new, :create ]

  before_action :set_boundary_recording, only: [ :edit, :update, :destroy ]
  before_action :authorize_manage_boundary!, only: [ :edit, :update, :destroy ]

  def new
    existing_boundary_recording = boundary_recording_for(@parent_recording)
    if existing_boundary_recording
      redirect_to(edit_boundary_recording_path(existing_boundary_recording, return_to: @return_to), alert: "Boundary already exists.")
      return
    end

    @boundary = RecordingStudio::AccessBoundary.new
  end

  def create
    existing_boundary_recording = boundary_recording_for(@parent_recording)
    if existing_boundary_recording
      redirect_to(edit_boundary_recording_path(existing_boundary_recording, return_to: @return_to), alert: "Boundary already exists.")
      return
    end

    minimum_role = normalized_minimum_role
    unless valid_minimum_role?(minimum_role)
      @boundary = RecordingStudio::AccessBoundary.new(minimum_role: minimum_role)
      flash.now[:alert] = "Minimum role is invalid."
      return render :new, status: :unprocessable_entity
    end

    (@parent_recording.root_recording || @parent_recording).record(
      RecordingStudio::AccessBoundary,
      actor: current_actor,
      impersonator: Current.impersonator,
      metadata: { source: "ui" },
      parent_recording: @parent_recording
    ) do |boundary|
      boundary.minimum_role = minimum_role
    end

    redirect_to(@return_to || default_return_path(@parent_recording), notice: "Boundary added.")
  end

  def edit
    @boundary = @boundary_recording.recordable
  end

  def update
    minimum_role = normalized_minimum_role
    unless valid_minimum_role?(minimum_role)
      @boundary = @boundary_recording.recordable
      flash.now[:alert] = "Minimum role is invalid."
      return render :edit, status: :unprocessable_entity
    end

    @boundary_recording.root_recording.revise(@boundary_recording, actor: current_actor) do |boundary|
      boundary.minimum_role = minimum_role
    end

    redirect_to(@return_to || default_return_path(@boundary_recording.parent_recording), notice: "Boundary updated.")
  end

  def destroy
    parent_recording = @boundary_recording.parent_recording

    @boundary_recording.root_recording.trash(
      @boundary_recording,
      actor: current_actor,
      impersonator: Current.impersonator,
      metadata: { source: "ui" }
    )

    redirect_to(@return_to || default_return_path(parent_recording), notice: "Boundary removed.")
  end

  private

  def set_parent_recording
    @parent_recording = RecordingStudio::Recording
      .includes(:root_recording, :recordable)
      .find(params[:parent_recording_id])
  end

  def set_boundary_recording
    @boundary_recording = RecordingStudio::Recording
      .includes(:root_recording, :parent_recording, :recordable)
      .find(params[:id])

    return if @boundary_recording.recordable_type == "RecordingStudio::AccessBoundary"

    raise ActiveRecord::RecordNotFound
  end

  def authorize_manage_parent_boundary!
    return if RecordingStudio::Services::AccessCheck.allowed?(
      actor: current_actor,
      recording: @parent_recording,
      role: :admin
    )

    redirect_to(@return_to || default_return_path(@parent_recording), alert: "You are not authorized to view this page.")
  end

  def authorize_manage_boundary!
    parent_recording = @boundary_recording.parent_recording
    return if RecordingStudio::Services::AccessCheck.allowed?(
      actor: current_actor,
      recording: parent_recording,
      role: :admin
    )

    redirect_to(@return_to || default_return_path(parent_recording), alert: "You are not authorized to view this page.")
  end

  def normalized_minimum_role
    params[:minimum_role].to_s.presence
  end

  def valid_minimum_role?(minimum_role)
    minimum_role.blank? || RecordingStudio::AccessBoundary.minimum_roles.key?(minimum_role)
  end

  def boundary_recording_for(recording)
    RecordingStudio::Recording.unscoped
      .where(parent_recording_id: recording.id, recordable_type: "RecordingStudio::AccessBoundary", trashed_at: nil)
      .order(created_at: :desc, id: :desc)
      .first
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

  def default_return_path(parent_recording)
    case parent_recording.recordable_type
    when "RecordingStudioFolder"
      folder_path(parent_recording)
    when "RecordingStudioPage"
      page_path(parent_recording)
    else
      recording_path(parent_recording)
    end
  end
end

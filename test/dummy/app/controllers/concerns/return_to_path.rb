# frozen_string_literal: true

module ReturnToPath
  extend ActiveSupport::Concern

  SAFE_RETURN_TO_PREFIXES = %w[
    /
    /access_recordings
    /actor_switch
    /actors
    /boundary_recordings
    /events
    /folders
    /pages
    /recordings
    /workspace_switches
    /workspaces
  ].freeze

  private

  def set_return_to
    @return_to = safe_return_to
  end

  def safe_return_to
    candidate = params[:return_to].presence || request.referer
    RecordingStudio::SafeReturnTo.sanitize(candidate, allowed_prefixes: safe_return_to_prefixes)
  end

  def safe_return_to_prefixes
    SAFE_RETURN_TO_PREFIXES
  end
end

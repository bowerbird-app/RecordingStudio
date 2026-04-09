module ApplicationHelper
  def workspace_switcher_options(current_actor:, current_root_recording:)
    return [ [], nil ] if current_actor.blank?

    root_ids = RecordingStudio::Services::AccessCheck.root_recording_ids_for(actor: current_actor)
    workspace_ids = RecordingStudio::Recording.unscoped.where(id: root_ids, recordable_type: "Workspace").pluck(:recordable_id)
    options = Workspace.where(id: workspace_ids).order(:name).map { |workspace| [ workspace.name, workspace.id ] }

    selected_workspace_id = if current_root_recording&.recordable_type == "Workspace"
      current_root_recording.recordable_id
    end

    [ options, selected_workspace_id ]
  end

  def actor_switcher_options(current_actor:, current_user:, true_user:, system_actors:, impersonating:)
    selected = if current_actor.is_a?(SystemActor)
      "SystemActor:#{current_actor.id}"
    elsif impersonating && current_actor.is_a?(User)
      "User:#{current_actor.id}"
    else
      ""
    end

    user_options = User.where.not(id: true_user.id).order(:name).map { |user| [ user.name, "User:#{user.id}" ] }
    system_options = system_actors.map { |system_actor| [ "#{system_actor.name} (System)", "SystemActor:#{system_actor.id}" ] }
    grouped_options = { "Users" => user_options }
    grouped_options["System actors"] = system_options if system_options.any?

    [ grouped_options, selected, "Signed in as #{true_user.name}" ]
  end

  def actor_label(actor)
    return "System" unless actor

    suffix = actor.is_a?(SystemActor) ? "System" : "User"
    "#{actor.name} (#{suffix})"
  end

  def actor_with_impersonator_label(actor, impersonator)
    label = actor_label(actor)
    return label unless impersonator

    "#{label} (impersonated by #{actor_label(impersonator)})"
  end

  def recordable_label(recordable)
    RecordingStudio::Labels.label_for(recordable)
  end

  def recordable_type_label(recordable_or_type)
    RecordingStudio::Labels.type_label_for(recordable_or_type)
  end

  def recordable_title(recordable)
    RecordingStudio::Labels.title_for(recordable)
  end

  def recordable_summary(recordable)
    RecordingStudio::Labels.summary_for(recordable)
  end
end

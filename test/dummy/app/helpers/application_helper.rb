module ApplicationHelper
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

  def recordable_name(recordable)
    RecordingStudio::Labels.name_for(recordable)
  end

  alias_method :recordable_label, :recordable_name

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

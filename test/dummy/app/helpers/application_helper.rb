module ApplicationHelper
  def actor_switcher_options(current_actor:, current_user:, true_user:, system_actors:, impersonating:)
    selected = if current_actor.is_a?(SystemActor)
      "SystemActor:#{current_actor.id}"
    elsif impersonating
      "User:#{current_user.id}"
    else
      ""
    end

    user_options = User.where.not(id: true_user.id).order(:name).map { |user| [user.name, "User:#{user.id}"] }
    system_options = system_actors.map { |system_actor| ["#{system_actor.name} (System)", "SystemActor:#{system_actor.id}"] }
    grouped_options = { "Users" => user_options }
    grouped_options["System actors"] = system_options if system_options.any?

    [grouped_options, selected, "Signed in as #{true_user.name}"]
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
    return "—" unless recordable

    if recordable.is_a?(RecordingStudio::Access)
      actor = recordable.actor
      role = recordable.role
      actor_text = actor ? actor_label(actor) : "Unknown actor"
      return "Access: #{role} — #{actor_text}"
    end

    if recordable.is_a?(RecordingStudio::AccessBoundary)
      minimum = recordable.minimum_role
      return minimum.present? ? "Access boundary (min: #{minimum})" : "Access boundary"
    end

    if (defined?(RecordingStudioComment) && recordable.is_a?(RecordingStudioComment)) || recordable.class.name == "RecordingStudio::Comment"
      body = recordable.body.to_s.squish
      snippet = body.present? ? truncate(body, length: 60) : ""
      return snippet.present? ? "Comment: #{snippet}" : "Comment"
    end

    recordable.respond_to?(:title) ? recordable.title : "#{recordable.class.name} ##{recordable.id}"
  end
end

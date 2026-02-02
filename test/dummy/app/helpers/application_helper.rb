module ApplicationHelper
  def actor_label(actor)
    return "System" unless actor

    suffix = actor.is_a?(ServiceAccount) ? "Service" : "User"
    "#{actor.name} (#{suffix})"
  end

  def recordable_label(recordable)
    return "—" unless recordable

    recordable.respond_to?(:title) ? recordable.title : "#{recordable.class.name} ##{recordable.id}"
  end
end

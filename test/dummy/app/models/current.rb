class Current < ActiveSupport::CurrentAttributes
  attribute :actor
  attribute :impersonator

  def self.reset_all
    reset
  end
end

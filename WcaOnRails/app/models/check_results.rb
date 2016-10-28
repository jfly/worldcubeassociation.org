# frozen_string_literal: true
class CheckResults
  include ActiveModel::Model

  attr_accessor :competition_id, :event_id, :what
  attr_reader :competition, :event

  def competition_id=(competition_id)
    @competition_id = competition_id
    @competition = Competition.find_by_id(competition_id)
  end

  def event_id=(event_id)
    @event_id = event_id
    @event = Event.find_by_id(event_id)
  end

  def what=(what)
    @what = what
  end

  validate :require_valid_competition_id
  def require_valid_competition_id
    if competition_id && !@competition
      errors.add(:competition_id, "invalid")
    end
  end

  validate :require_valid_event_id
  def require_valid_event_id
    if event_id && !@event
      errors.add(:event_id, "invalid")
    end
  end

  def warnings
    warnings = []
    warnings << "don't do that" #<<<
    warnings
  end
end

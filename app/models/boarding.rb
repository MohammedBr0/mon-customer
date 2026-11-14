# frozen_string_literal: true

# One passenger on one day of a ride: picked up, didn't show, or dropped off.
class Boarding < ApplicationRecord
  belongs_to :booking

  def status
    return 'dropped_off' if dropped_off_at
    return 'no_show' if no_show_at
    return 'boarded' if boarded_at

    'waiting'
  end

  # Picked up, or a no-show: the driver doesn't need to wait for them before setting off.
  def resolved?
    boarded_at.present? || no_show_at.present?
  end
end

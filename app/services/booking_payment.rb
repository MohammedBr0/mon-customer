# frozen_string_literal: true

# Moves a wallet-paid seat's money through its life: set aside when the seat is requested, returned if the
# request is declined or cancelled, and paid to the driver (less the platform fee) once the ride is done.
class BookingPayment
  RELEASE_AFTER = 24.hours
  # What the driver keeps of the fare when a passenger cancels late (share of the fare, by hours before departure).
  LATE_CANCEL = [[2, 1.0], [24, 0.5]].freeze

  def initialize(booking)
    @booking = booking
  end

  def wallet?
    @booking.payment_method == 'wallet'
  end

  # Sets the money aside when the passenger asks for the seat. Raises Wallet::InsufficientFunds if they cannot cover it.
  def hold!
    return unless wallet?

    amount = @booking.passenger_total
    Wallet.for(@booking.passenger).move!('hold', available: -amount, held: amount, subject: @booking, memo: @booking.itinerary.title)
    @booking.update_columns(payment_state: 'held', held_amount: amount)
  end

  # A skipped day costs less: the difference goes back to the passenger.
  def adjust_hold!
    return unless wallet? && @booking.payment_state == 'held'

    difference = @booking.held_amount - @booking.passenger_total
    return unless difference.positive?

    Wallet.for(@booking.passenger).move!('refund', available: difference, held: -difference, subject: @booking, memo: 'skipped day')
    @booking.update_columns(held_amount: @booking.passenger_total)
  end

  # The seat did not happen. Who cancelled, and how late, decides how the held money is split.
  def cancel!(by:)
    return unless wallet? && @booking.payment_state == 'held'

    share = by == @booking.passenger && @booking.status_before_last_save == 'confirmed' ? driver_share_on_cancel : 0
    if share.zero?
      refund_all!
    else
      held = @booking.held_amount
      to_driver = (@booking.fare_total * share).round(2)
      fee = driver_pays_fee? ? (to_driver * @booking.fee_percent / 100).round(2) : 0
      to_passenger = held - to_driver
      Wallet.transaction do
        Wallet.for(@booking.passenger).move!('refund', available: to_passenger, held: -held, subject: @booking, memo: 'late cancellation')
        Wallet.for(@booking.driver).move!('earning', available: to_driver - fee, subject: @booking, memo: 'late cancellation')
        Wallet.platform.move!('fee', available: fee, subject: @booking) if fee.positive?
        @booking.update_columns(payment_state: 'refunded', held_amount: 0, settled_at: Time.current)
      end
      Notification.notify(@booking.passenger, 'payment_refunded', amount: ApiSerializer.money(to_passenger).to_s, trip: @booking.itinerary.title)
    end
  end

  def refund_all!
    return unless wallet? && @booking.payment_state == 'held'

    held = @booking.held_amount
    Wallet.for(@booking.passenger).move!('refund', available: held, held: -held, subject: @booking, memo: @booking.itinerary.title)
    @booking.update_columns(payment_state: 'refunded', held_amount: 0, settled_at: Time.current)
    Notification.notify(@booking.passenger, 'payment_refunded', amount: ApiSerializer.money(held).to_s, trip: @booking.itinerary.title)
  end

  # The ride is done: the driver gets their share, the platform its fee.
  def release!
    return false unless wallet? && @booking.payment_state == 'held' && @booking.confirmed?

    Wallet.transaction do
      @booking.lock!
      return false unless @booking.payment_state == 'held'

      held = @booking.held_amount
      payout = [@booking.driver_payout, held].min
      Wallet.for(@booking.passenger).move!('payment', held: -held, subject: @booking, memo: @booking.itinerary.title)
      Wallet.for(@booking.driver).move!('earning', available: payout, subject: @booking, memo: @booking.itinerary.title)
      Wallet.platform.move!('fee', available: held - payout, subject: @booking) if held > payout
      @booking.update_columns(payment_state: 'released', held_amount: 0, settled_at: Time.current)
    end
    Notification.notify(@booking.driver, 'payment_received', amount: ApiSerializer.money(@booking.driver_payout).to_s, trip: @booking.itinerary.title, person: @booking.passenger.to_s)
    true
  end

  # True once the ride is over and the waiting time has passed, or the passenger said it went well.
  def due?
    return false unless wallet? && @booking.payment_state == 'held' && @booking.confirmed?
    return true if @booking.passenger_confirmed_at.present?

    finished_at = @booking.ride_finished_at
    finished_at.present? && finished_at <= RELEASE_AFTER.ago
  end

  # Pays out every seat whose time has come. There is no background worker, so this runs whenever someone
  # opens their bookings or wallet, and from the admin page.
  def self.settle_due!(scope = Booking.all)
    scope.where(payment_method: 'wallet', payment_state: 'held', status: 'confirmed').includes(:itinerary, :passenger).find_each.count do |booking|
      payment = new(booking)
      payment.due? && payment.release!
    end
  end

  private

  def driver_pays_fee?
    @booking.fee_charged_to != 'passenger'
  end

  def driver_share_on_cancel
    start = @booking.first_ride_at
    return 0 unless start

    hours = (start - Time.current) / 3600.0
    LATE_CANCEL.each { |limit, share| return share if hours < limit }
    0
  end
end

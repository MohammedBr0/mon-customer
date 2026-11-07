# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RideAlert do
  let(:user) { create(:user) }
  # Addis Ababa -> Adama
  let(:alert) { create(:ride_alert, user:) }

  def trip(start_lng_lat: [38.7525, 9.0192], end_lng_lat: [39.2695, 8.54], **attributes)
    create(:itinerary, start_location: start_lng_lat, end_location: end_lng_lat, **attributes)
  end

  it 'matches trips that start and end near the saved route' do
    alert
    near = trip(start_lng_lat: [38.76, 9.02], end_lng_lat: [39.27, 8.55])
    far_end = trip(end_lng_lat: [41.87, 9.59]) # Dire Dawa
    far_start = trip(start_lng_lat: [37.39, 11.59]) # Bahir Dar

    matches = described_class.matching(near)
    expect(matches).to include(alert)
    expect(described_class.matching(far_end)).not_to include(alert)
    expect(described_class.matching(far_start)).not_to include(alert)
  end

  it 'never alerts the driver about their own trip, nor when switched off' do
    alert
    own = trip(user:)
    expect(described_class.matching(own)).to be_empty

    alert.update!(active: false)
    expect(described_class.matching(trip)).to be_empty
  end

  it 'lists the open trips that already match' do
    match = trip
    trip(end_lng_lat: [41.87, 9.59])
    cancelled = trip
    cancelled.cancel!

    expect(alert.current_matches).to eq [match]
  end

  it 'is built from the search form coordinates' do
    built = described_class.from_search(user, { from: 'Addis Ababa', to: 'Adama', start_location_lng: '38.75', start_location_lat: '9.01',
                                                end_location_lng: '39.27', end_location_lat: '8.54' })

    expect(built).to be_valid
    expect(described_class.from_search(user, { from: 'Addis Ababa', to: 'Adama' })).not_to be_valid
  end

  it 'caps the number of alerts per person' do
    create_list(:ride_alert, described_class::MAX_PER_USER, user:)

    expect(build(:ride_alert, user:)).not_to be_valid
  end

  describe RideAlertMatchJob do
    it 'emails everyone whose route matches the new trip and records it' do
      alert
      other = create(:ride_alert, user: create(:user, gender: 'female'), start_location: [38.75, 9.02], end_location: [39.27, 8.54])

      expect { described_class.perform_now(trip) }.to have_enqueued_mail(AlertMailer, :match).twice
      expect(alert.reload.last_notified_at).to be_present
      expect(other.reload.last_notified_at).to be_present
    end

    it 'keeps women-only trips from alerting men' do
      alert
      driver = create(:user, gender: 'female')

      expect { described_class.perform_now(trip(user: driver, pink: true)) }.not_to have_enqueued_mail(AlertMailer, :match)
    end

    it 'sends nothing for a cancelled trip' do
      alert
      cancelled = trip
      cancelled.cancel!

      expect { described_class.perform_now(cancelled) }.not_to have_enqueued_mail(AlertMailer, :match)
    end
  end
end

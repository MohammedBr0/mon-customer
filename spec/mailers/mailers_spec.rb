# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mailers' do
  let(:driver) { create(:user, name: 'Dave Driver', email: 'dave@example.com') }
  let(:passenger) { create(:user, name: 'Paula Passenger', email: 'paula@example.com') }
  let(:itinerary) { create(:itinerary, user: driver, num_people: 3, start_address: 'Milan', end_address: 'Turin') }
  let(:booking) { create(:booking, itinerary:, passenger:, seats: 2, note: 'At the station') }

  describe BookingMailer do
    it 'tells the driver about a request' do
      mail = described_class.with(booking:).requested

      expect(mail.to).to eq ['dave@example.com']
      expect(mail.subject).to include('Paula Passenger', 'Milan - Turin')
      expect(mail.body.encoded).to include('2 seat(s)', 'At the station', itinerary_url(itinerary))
    end

    it 'tells the passenger about a confirmation and a refusal' do
      expect(described_class.with(booking:).confirmed.to).to eq ['paula@example.com']
      expect(described_class.with(booking:).declined.to).to eq ['paula@example.com']
    end

    it 'tells the other side about a cancellation' do
      booking.cancel!(by: passenger)
      expect(described_class.with(booking:).cancelled.to).to eq ['dave@example.com']

      other = create(:booking, itinerary:, passenger: create(:user, email: 'other@example.com'))
      other.cancel!(by: driver)
      expect(described_class.with(booking: other).cancelled.to).to eq ['other@example.com']
    end

    it 'writes in the recipient language' do
      passenger.update!(locale: 'it-IT')

      expect(described_class.with(booking:).confirmed.subject).to eq 'La tua prenotazione su Milan - Turin è confermata'
    end
  end

  describe ItineraryMailer do
    it 'tells a passenger the trip was cancelled' do
      mail = described_class.with(booking:).cancelled

      expect(mail.to).to eq ['paula@example.com']
      expect(mail.subject).to include('Trip cancelled')
    end
  end

  describe MessageMailer do
    let(:conversation) { create(:conversation, conversable: itinerary, sender: passenger, receiver: driver) }

    it 'emails the recipient a new message' do
      message = create(:message, conversation:, sender: passenger, body: 'Is there room?')
      mail = described_class.with(message:).new_message

      expect(mail.to).to eq ['dave@example.com']
      expect(mail.body.encoded).to include('Is there room?')
    end

    it 'sends only when the recipient enabled email notifications' do
      expect { create(:message, conversation:, sender: passenger) }.not_to have_enqueued_mail(MessageMailer, :new_message)

      driver.update!(send_email_messages: true)
      expect { create(:message, conversation:, sender: passenger) }.to have_enqueued_mail(MessageMailer, :new_message)
    end
  end
end

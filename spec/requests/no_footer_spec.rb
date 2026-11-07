# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'No footer and no open-source wording' do
  let(:user) { create(:user, name: 'Dawit Driver') }
  let(:itinerary) { create(:itinerary, user:) }
  let(:forbidden) { /open[- ]?source|github|source code|diowa|company ?carpool|repository|sorgente|ክፍት ምንጭ/i }
  let(:public_pages) { %i[root_path about_path how_it_works_path terms_path privacy_path] }

  %w[en-US am-ET it-IT].each do |locale|
    it "keeps every public page free of a footer and open-source text in #{locale}" do
      public_pages.each do |route|
        get public_send(route, locale:)

        expect(response.body).not_to include('app-footer'), "#{route} still has a footer"
        expect(response.body).not_to match(forbidden), "#{route} mentions open source: #{response.body[forbidden]}"
      end
    end

    it "keeps signed-in pages free of a footer and open-source text in #{locale}" do
      sign_in user
      [dashboard_path(locale:), settings_path(locale:), bookings_path(locale:), itinerary_path(itinerary, locale:), new_itinerary_path(locale:)].each do |path|
        get path

        expect(response.body).not_to include('app-footer'), "#{path} still has a footer"
        expect(response.body).not_to match(forbidden), "#{path} mentions open source: #{response.body[forbidden]}"
      end
    end
  end

  it 'uses a neutral page title on the landing page' do
    get root_path

    expect(response.body).to include('<title>Share the ride across Ethiopia')
  end

  it 'keeps the legal and account links reachable from the signed-in menu' do
    sign_in user

    get dashboard_path

    %w[/about /how_it_works /terms /privacy /feedbacks].each { |path| expect(response.body).to include("href=\"#{path}\"") }
  end

  it 'offers the same links to visitors in the top bar and on the landing page' do
    get terms_path

    %w[/about /how_it_works /terms /privacy].each { |path| expect(response.body).to include("href=\"#{path}\"") }

    get root_path
    expect(response.body).to include('href="/how_it_works"', 'href="/about"')
  end

  it 'moves account deletion to the settings page' do
    sign_in user

    get settings_path
    expect(response.body).to include("href=\"/users/#{user.id}\"", 'data-method="delete"', 'Delete account')

    expect { delete user_path(user) }.to change(User, :count).by(-1)
  end
end

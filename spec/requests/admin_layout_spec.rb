# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin side menu and dashboard' do
  let(:admin) { create(:user, admin: true, name: 'Sara Admin') }
  let(:moderator) { create(:user, moderator: true) }

  before do
    driver = create(:user, app_mode: 'driver')
    trip = create(:itinerary, user: driver)
    create(:booking, itinerary: trip, passenger: create(:user))
    IdentityDocument.create!(user: driver, kind: 'national_id', number: '1234567890123456', image: 'img', content_type: 'image/jpeg')
  end

  it 'shows a super admin every section, with counts of what is waiting' do
    sign_in admin
    get '/admin'
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include('admin-side', 'Overview', 'People', 'Operations', 'Configuration', 'Security')
    expect(body).to include('Payment methods', 'Identity checks', 'Audit log', 'Needs your attention', 'Hello, Sara')
    expect(body).to match(%r{admin-side__badge[^>]*>1<})
    expect(body).not_to include('translation missing', 'tabbar')
    File.write(Rails.root.join('tmp/admin_dashboard.html'), body) if ENV['DUMP_HTML']
  end

  it 'hides configuration and money from moderators' do
    sign_in moderator
    get '/admin'
    expect(response.body).to include('Operations', 'Identity checks')
    expect(response.body).not_to include('Configuration', 'Payment methods', 'Audit log', 'money-row')
  end

  it 'uses the same layout on every admin page, marking where you are' do
    sign_in admin
    %w[/admin/users /admin/identity_documents /admin/payment_methods /admin/settings /admin/reports /admin/bookings /admin/itineraries /admin/reviews /admin/vehicle_fields /admin/popular_routes /admin/audit_logs].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
      expect(response.body).to include('admin-side__link active'), path
      expect(response.body).not_to include('translation missing'), path
    end
  end
end

RSpec.describe 'Where people land' do
  it 'sends a super admin to the admin dashboard, and everyone else to their own' do
    sign_in create(:user, admin: true)
    get '/'
    expect(response).to redirect_to('/admin')
    get '/dashboard' # "Back to the site" still works
    expect(response).to have_http_status(:ok)
    sign_out :user

    sign_in create(:user, moderator: true)
    get '/'
    expect(response).to redirect_to('/dashboard')
    sign_out :user

    sign_in create(:user)
    get '/'
    expect(response).to redirect_to('/dashboard')
  end

end

RSpec.describe 'Admin announcements' do
  let(:admin) { create(:user, admin: true) }

  it 'puts the message in the chosen people\'s notifications' do
    driver = create(:user, app_mode: 'driver')
    passenger = create(:user, app_mode: 'passenger')
    banned = create(:user, banned: true)
    sign_in admin

    post '/admin/announcements', params: { title: 'Holiday schedule', body: 'Fewer rides on Thursday.', audience: 'drivers' }
    expect(response).to redirect_to('/admin/announcements')
    expect(driver.notifications.pluck(:kind)).to eq ['announcement']
    expect(passenger.notifications).to be_empty

    post '/admin/announcements', params: { title: 'Welcome', body: 'Thanks for joining.', audience: 'everyone' }
    expect(passenger.notifications.count).to eq 1
    expect(banned.notifications).to be_empty

    get '/api/v1/notifications', headers: api_headers(passenger)
    expect(json['notifications'].first).to include('kind' => 'announcement', 'title' => 'Welcome', 'body' => 'Thanks for joining.', 'read' => false)

    get '/admin/announcements'
    expect(response.body).to include('Holiday schedule', 'Drivers only')
  end

  it 'needs a title and a message, and a super admin' do
    sign_in admin
    expect { post '/admin/announcements', params: { title: '', body: 'x' } }.not_to change(Notification, :count)
    expect(response).to have_http_status(:unprocessable_entity)

    sign_out admin
    sign_in create(:user, moderator: true)
    expect { post '/admin/announcements', params: { title: 'Hi', body: 'There' } }.not_to change(Notification, :count)
  end
end

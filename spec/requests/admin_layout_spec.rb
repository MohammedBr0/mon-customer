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

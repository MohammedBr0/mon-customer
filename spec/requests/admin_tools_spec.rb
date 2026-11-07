# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super admin and moderator tools' do
  let(:super_admin) { create(:user, name: 'Sara Super', admin: true) }
  let(:moderator) { create(:user, name: 'Mulu Moderator', moderator: true) }
  let(:member) { create(:user, name: 'Mesfin Member', email: 'mesfin@example.com', phone: '+251911000111') }
  let(:driver) { create(:user, name: 'Dawit Driver') }
  let(:itinerary) { create(:itinerary, user: driver, num_people: 3, price_per_seat: 100, start_address: 'Addis Ababa', end_address: 'Adama') }

  describe 'roles' do
    it 'gives moderators the staff pages but not money, configuration or the audit log' do
      sign_in moderator

      %i[admin_root_path admin_users_path admin_reports_path admin_bookings_path admin_itineraries_path admin_reviews_path].each do |route|
        get public_send(route)
        expect(response).to have_http_status(:ok), "#{route} should open for a moderator"
      end

      %i[admin_settings_path admin_vehicle_fields_path admin_popular_routes_path admin_audit_logs_path].each do |route|
        get public_send(route)
        expect(response).to redirect_to(admin_root_path), "#{route} should be closed to a moderator"
      end
    end

    it 'hides money from moderators on the dashboard' do
      create(:booking, :confirmed, itinerary:, seats: 1)
      sign_in moderator
      get admin_root_path
      expect(response.body).not_to include(I18n.t('admin_extra.stats.gross_fares'))

      sign_in super_admin
      get admin_root_path
      expect(response.body).to include(I18n.t('admin_extra.stats.gross_fares'))
    end

    it 'keeps ordinary members out of everything' do
      sign_in member

      get admin_users_path
      expect(response).to redirect_to(root_path)
      get admin_reports_path
      expect(response).to redirect_to(root_path)
    end

    it 'lets only a super admin change roles, never their own' do
      sign_in super_admin
      patch set_role_admin_user_path(member), params: { role: 'moderator' }
      expect(member.reload).to be_moderator
      expect(member).not_to be_admin

      patch set_role_admin_user_path(member), params: { role: 'admin' }
      expect(member.reload).to be_admin
      expect(member).not_to be_moderator

      patch set_role_admin_user_path(member), params: { role: 'user' }
      expect(member.reload).not_to be_staff

      patch set_role_admin_user_path(super_admin), params: { role: 'user' }
      expect(super_admin.reload).to be_admin

      patch set_role_admin_user_path(member), params: { role: 'owner' }
      expect(member.reload).not_to be_staff
    end

    it 'does not let a moderator promote anyone or impersonate' do
      sign_in moderator

      patch set_role_admin_user_path(member), params: { role: 'admin' }
      expect(member.reload).not_to be_admin

      get login_as_admin_user_path(member)
      expect(response).to redirect_to(admin_root_path)
    end
  end

  describe 'user management' do
    before do
      member
      driver
      sign_in moderator
    end

    it 'searches by name, email or phone and filters' do
      get admin_users_path(q: 'mesfin')
      expect(response.body).to include('Mesfin Member')
      expect(response.body).not_to include('Dawit Driver')

      get admin_users_path(q: '911000111')
      expect(response.body).to include('Mesfin Member')

      driver.update!(banned: true)
      get admin_users_path(filter: 'banned')
      expect(response.body).to include('Dawit Driver')
      expect(response.body).not_to include('Mesfin Member')

      get admin_users_path(filter: 'staff')
      expect(response.body).to include('Mulu Moderator')
    end

    it 'shows a person with their trips, bookings, vehicle and reports' do
      create(:vehicle_field, key: 'make', label: 'Make')
      driver.update!(vehicle_data: { 'make' => 'Toyota' })
      create(:report, reportable: driver, reporter: member, reason: 'harassment')
      itinerary
      create(:booking, itinerary:, passenger: member)

      get admin_user_path(driver)

      expect(response.body).to include('Dawit Driver', 'Make: Toyota', 'Addis Ababa', 'Harassment or abuse')
    end

    it 'verifies and unverifies a driver, shows the badge and records who did it' do
      post verify_admin_user_path(driver)
      expect(driver.reload).to be_verified
      expect(driver.verified_by).to eq moderator

      get itinerary_path(itinerary)
      expect(response.body).to include('Verified')

      post unverify_admin_user_path(driver)
      expect(driver.reload).not_to be_verified
    end

    it 'bans and unbans, but never the staff member themselves' do
      post ban_admin_user_path(member)
      expect(member.reload).to be_banned

      post unban_admin_user_path(member)
      expect(member.reload).not_to be_banned

      post ban_admin_user_path(moderator)
      expect(moderator.reload).not_to be_banned
    end
  end

  describe 'reports queue' do
    let!(:report) { create(:report, reportable: itinerary, reporter: member, reason: 'fake_or_scam', details: 'Asked for money upfront') }

    before { sign_in moderator }

    it 'lists open reports and shows the detail' do
      get admin_reports_path
      expect(response.body).to include('Fake listing or scam', 'Addis Ababa')

      get admin_report_path(report)
      expect(response.body).to include('Asked for money upfront', 'Cancel the trip')
    end

    it 'resolves a report and cancels the reported trip in one step' do
      booking = create(:booking, :confirmed, itinerary:)

      patch resolve_admin_report_path(report), params: { outcome: 'resolve', action_taken: 'cancel_trip', note: 'Confirmed scam' }

      expect(report.reload).to have_attributes(status: 'resolved', resolved_by: moderator, resolution_note: 'Confirmed scam')
      expect(itinerary.reload).to be_cancelled
      expect(booking.reload).to be_cancelled
    end

    it 'can ban the reported driver' do
      patch resolve_admin_report_path(report), params: { outcome: 'resolve', action_taken: 'ban_user' }

      expect(driver.reload).to be_banned
    end

    it 'dismisses without touching the trip and moves it to the dismissed list' do
      patch resolve_admin_report_path(report), params: { outcome: 'dismiss', note: 'No issue found' }

      expect(report.reload.status).to eq 'dismissed'
      expect(itinerary.reload).not_to be_cancelled
      get admin_reports_path(status: 'dismissed')
      expect(response.body).to include('Addis Ababa')
    end

    it 'hides a reported review' do
      booking = create(:booking, :completed)
      review = create(:review, booking:, comment: 'Abusive text')
      review_report = create(:report, reportable: review, reporter: member, reason: 'inappropriate')

      patch resolve_admin_report_path(review_report), params: { outcome: 'resolve', action_taken: 'hide_review' }

      expect(review.reload).to be_hidden
    end
  end

  describe 'review moderation' do
    let(:booking) { create(:booking, :completed) }
    let!(:review) { create(:review, booking:, rating: 1, comment: 'Awful', reviewee: booking.driver) }

    before { sign_in moderator }

    it 'hides a review so it stops counting, and shows it again' do
      expect(booking.driver.average_rating).to eq 1.0

      patch hide_admin_review_path(review)
      expect(review.reload).to be_hidden
      expect(booking.driver.average_rating).to be_nil
      expect(booking.driver.reviews_count).to eq 0

      get user_path(booking.driver)
      expect(response.body).not_to include('Awful')

      patch unhide_admin_review_path(review)
      expect(booking.driver.reload.average_rating).to eq 1.0
    end

    it 'filters low-rated and hidden reviews' do
      get admin_reviews_path(filter: 'low')
      expect(response.body).to include('Awful')

      get admin_reviews_path(filter: 'hidden')
      expect(response.body).not_to include('Awful')
    end
  end

  describe 'bookings oversight and export' do
    let!(:booking) { create(:booking, itinerary:, passenger: member, seats: 2) }

    it 'filters bookings and lets staff cancel one' do
      sign_in moderator
      get admin_bookings_path(status: 'pending', q: 'Mesfin')
      expect(response.body).to include('Addis Ababa')
      get admin_bookings_path(status: 'confirmed')
      expect(response.body).not_to include('Addis Ababa')

      expect { patch cancel_admin_booking_path(booking) }.to have_enqueued_mail(BookingMailer, :cancelled)
      expect(booking.reload).to be_cancelled
    end

    it 'exports money details as CSV for a super admin, with the audit trail' do
      PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
      sign_in super_admin

      expect { get admin_bookings_path(format: :csv) }.to change(AuditLog, :count).by(1)

      expect(response.media_type).to eq 'text/csv'
      csv = CSV.parse(response.body, headers: true)
      expect(csv.headers).to include('fare', 'fee', 'passenger_total', 'driver_payout', 'driver_phone')
      expect(csv.first.to_h).to include('passenger' => 'Mesfin Member', 'seats' => '2', 'days' => '1', 'fee' => '20.0', 'passenger_total' => '220.0')
    end

    it 'keeps the CSV away from moderators' do
      sign_in moderator

      get admin_bookings_path(format: :csv)

      expect(response).to redirect_to(admin_bookings_path(format: :html))
      expect(response.body).not_to include('passenger_total')
    end
  end

  describe 'audit log' do
    it 'records staff actions with who, what and the details' do
      sign_in super_admin

      patch admin_settings_path, params: { platform_setting: { fee_percent: '15' } }
      post ban_admin_user_path(member)
      patch cancel_admin_itinerary_path(itinerary)

      logs = AuditLog.recent.to_a
      expect(logs.map(&:action)).to include('settings.update', 'user.ban', 'itinerary.cancel')
      settings_log = logs.find { |log| log.action == 'settings.update' }
      expect(settings_log.actor).to eq super_admin
      expect(settings_log.details['fee_percent']).to eq('from' => '10.0', 'to' => '15.0')

      get admin_audit_logs_path
      expect(response.body).to include('settings.update', 'user.ban', 'Sara Super')
      get admin_audit_logs_path(prefix: 'user')
      expect(response.body).to include('user.ban')
      expect(response.body).not_to include('settings.update')
    end

    it 'cannot be edited or deleted once written' do
      log = AuditLog.record(super_admin, 'test.action')

      expect { log.update!(action: 'changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { log.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'logs moderator actions too' do
      sign_in moderator
      post verify_admin_user_path(driver)

      expect(AuditLog.last).to have_attributes(action: 'user.verify', actor: moderator, subject_label: 'Dawit Driver')
    end
  end

  describe 'announcement banner and commute settings' do
    it 'shows the announcement to everyone while it is active' do
      sign_in super_admin
      patch admin_settings_path, params: { platform_setting: { announcement: 'Maintenance on Sunday 2am', announcement_active: '1' } }

      sign_out super_admin
      get root_path
      expect(response.body).to include('Maintenance on Sunday 2am')

      sign_in member
      get dashboard_path
      expect(response.body).to include('Maintenance on Sunday 2am')

      PlatformSetting.current.update!(announcement_active: false)
      get dashboard_path
      expect(response.body).not_to include('Maintenance on Sunday 2am')
    end

    it 'validates the commute horizon' do
      sign_in super_admin

      patch admin_settings_path, params: { platform_setting: { commute_horizon_days: '90' } }
      expect(response).to have_http_status(:unprocessable_entity)

      patch admin_settings_path, params: { platform_setting: { commute_horizon_days: '30', commutes_enabled: '0' } }
      expect(PlatformSetting.current).to have_attributes(commute_horizon_days: 30, commutes_enabled: false)
    end
  end

  describe 'popular routes' do
    it 'manages the shortcuts shown on the landing page' do
      sign_in super_admin

      post admin_popular_routes_path, params: { popular_route: { from_label: 'Addis Ababa', to_label: 'Jimma', active: '1' } }
      post admin_popular_routes_path, params: { popular_route: { from_label: 'Addis Ababa', to_label: 'Mekelle', active: '1' } }
      first, second = PopularRoute.ordered.to_a
      expect([first.to_s, second.to_s]).to eq ['Addis Ababa → Jimma', 'Addis Ababa → Mekelle']

      patch move_admin_popular_route_path(second, direction: 'up')
      expect(PopularRoute.ordered.first).to eq second

      patch admin_popular_route_path(first), params: { popular_route: { from_label: 'Addis Ababa', to_label: 'Jimma', active: '0' } }
      sign_out super_admin
      get root_path
      expect(response.body).to include('Addis Ababa → Mekelle')
      expect(response.body).not_to include('Addis Ababa → Jimma')

      sign_in super_admin
      delete admin_popular_route_path(second)
      expect(PopularRoute.exists?(second.id)).to be false
    end

    it 'falls back to the default shortcuts when none are set' do
      get root_path

      expect(response.body).to include('Addis Ababa → Adama')
    end

    it 'rejects blank labels' do
      sign_in super_admin

      post admin_popular_routes_path, params: { popular_route: { from_label: '', to_label: 'Jimma' } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

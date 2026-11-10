# frozen_string_literal: true

module AdminHelper
  # The side menu: groups of [key, path, label, icon, badge]. Super-admin-only groups are hidden from moderators.
  def admin_menu
    groups = [
      [t('admin_menu.overview'), [[:dashboard, admin_root_path, t('admin_extra.dashboard'), 'gauge-high', nil]]],
      [t('admin_menu.people'), [
        [:users, admin_users_path, t('admin_extra.users'), 'users', nil],
        [:identity_documents, admin_identity_documents_path, t('identity.admin_title'), 'id-card', IdentityDocument.pending.count]
      ]],
      [t('admin_menu.operations'), [
        [:itineraries, admin_itineraries_path, t('admin_menu.trips'), 'route', nil],
        [:bookings, admin_bookings_path, t('admin_extra.bookings'), 'ticket', nil],
        [:reviews, admin_reviews_path, t('admin_extra.reviews'), 'star', nil],
        [:reports, admin_reports_path, t('admin_extra.reports'), 'flag', Report.open.count]
      ]]
    ]
    return groups unless current_user.super_admin?

    groups + [
      [t('admin_menu.configuration'), [
        [:settings, admin_settings_path, t('admin_extra.platform_settings'), 'sliders', nil],
        [:payment_methods, admin_payment_methods_path, t('payments.admin_title'), 'credit-card', nil],
        [:vehicle_fields, admin_vehicle_fields_path, t('admin_extra.vehicle_fields'), 'car', nil],
        [:popular_routes, admin_popular_routes_path, t('admin_extra.popular_routes'), 'location-dot', nil]
      ]],
      [t('admin_menu.security'), [[:audit_logs, admin_audit_logs_path, t('admin_extra.audit_log'), 'clipboard-list', nil]]]
    ]
  end

  def admin_menu_active?(key)
    controller_name == key.to_s
  end
end

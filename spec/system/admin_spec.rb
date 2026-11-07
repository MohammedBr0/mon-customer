# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin' do
  let!(:admin) { create(:user, admin: true, uid: '123456') }

  before do
    login_via_neon
  end

  #   it "sees reports" do
  #     expect(page).to have_css('#navbar-notifications-reports')
  #   end

  it 'sees users index' do
    visit admin_users_path

    expect(page).to have_current_path admin_users_path
  end

  it 'is able to ban other users from their page' do
    user_to_ban = create(:user)

    visit admin_user_path(user_to_ban)

    click_on t('helpers.links.user.ban')

    expect(page).to have_content t('flash.admin.users.success.ban')
    expect(user_to_ban.reload).to be_banned
  end

  it 'does not offer to ban himself' do
    visit admin_user_path(admin)

    expect(page).to have_no_button t('helpers.links.user.ban')
  end

  it 'is able to unban banned users' do
    banned_user = create(:user, banned: true)

    visit admin_user_path(banned_user)

    click_on t('helpers.links.user.unban')

    expect(page).to have_content t('flash.admin.users.success.unban')
    expect(banned_user.reload).not_to be_banned
  end

  it 'finds users by name from the list' do
    create(:user, name: 'Findable Person')

    visit admin_users_path(q: 'findable')

    expect(page).to have_content 'Findable Person'
  end

  it 'could login as another user' do
    regular_user = create(:user, name: 'act_as_me')

    visit login_as_admin_user_path(regular_user.id)

    expect(page).to have_current_path dashboard_path
    expect(page).to have_content regular_user.name
  end
end

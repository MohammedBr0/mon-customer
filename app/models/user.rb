# frozen_string_literal: true

class User < ApplicationRecord
  include NeonAuthOmniauthable
  include VehicleDetails

  # Include default devise modules. Others available are:
  devise :omniauthable, omniauth_providers: [:neon]
  # :confirmable, :lockable, :timeoutable and :omniauthable
  # :database_authenticatable, :registerable,
  # :recoverable, :rememberable, :trackable, :validatable

  GENDER = %w[male female].freeze

  paginates_per 25

  has_many :feedbacks, dependent: :nullify

  has_many :itineraries, dependent: :destroy
  has_many :ride_alerts, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :notifications, dependent: :delete_all
  has_many :reports_made, class_name: 'Report', foreign_key: :reporter_id, inverse_of: :reporter, dependent: :destroy
  belongs_to :verified_by, class_name: 'User', optional: true
  has_many :bookings, foreign_key: :passenger_id, inverse_of: :passenger, dependent: :destroy
  has_many :cancelled_bookings, class_name: 'Booking', foreign_key: :cancelled_by_id, inverse_of: :cancelled_by, dependent: :nullify
  has_many :reviews_received, class_name: 'Review', foreign_key: :reviewee_id, inverse_of: :reviewee, dependent: :destroy
  has_many :reviews_written, class_name: 'Review', foreign_key: :reviewer_id, inverse_of: :reviewer, dependent: :destroy

  has_many :conversations, ->(user) { unscope(:where).where(sender: user).or(where(receiver: user)) }, inverse_of: :sender, dependent: :destroy

  validates :gender, inclusion: GENDER, allow_blank: true
  validates :time_zone, inclusion: ActiveSupport::TimeZone.all.map(&:name)
  validates :vehicle_avg_consumption, numericality: { greater_than: 0, less_than: 1000 }, presence: true

  def age
    ((Time.current.to_fs(:number).to_i - birthday.at_midnight.to_fs(:number).to_i) / 1e10.to_i) if birthday?
  end

  def female?
    gender == 'female'
  end

  def first_name
    @first_name ||= name.split[0] if name?
  end

  def to_s
    name || id.to_s
  end

  # Hidden reviews (removed by a moderator) do not count.
  def average_rating
    reviews_received.visible.average(:rating)&.to_f&.round(1)
  end

  def reviews_count
    reviews_received.visible.count
  end

  def verified?
    verified_at.present?
  end

  # Super admins can do everything; moderators handle bans, reports and reviews.
  def super_admin?
    admin?
  end

  def staff?
    admin? || moderator?
  end

  def role_name
    return 'super_admin' if admin?

    moderator? ? 'moderator' : 'user'
  end

  def unread_conversations_count
    conversations.unread(self).count
  end

  def self.from_omniauth(auth_hash)
    where(provider: auth_hash.provider, uid: auth_hash.uid).first_or_create do |user|
      user.email = auth_hash.info.email
      user.image = auth_hash.info.image
      user.name  = auth_hash.info.name
    end
  end
end

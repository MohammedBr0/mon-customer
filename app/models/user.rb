# frozen_string_literal: true

class User < ApplicationRecord
  include NeonAuthOmniauthable

  # Include default devise modules. Others available are:
  devise :omniauthable, omniauth_providers: [:neon]
  # :confirmable, :lockable, :timeoutable and :omniauthable
  # :database_authenticatable, :registerable,
  # :recoverable, :rememberable, :trackable, :validatable

  GENDER = %w[male female].freeze

  paginates_per 25

  has_many :feedbacks, dependent: :nullify

  has_many :itineraries, dependent: :destroy
  has_many :bookings, foreign_key: :passenger_id, inverse_of: :passenger, dependent: :destroy
  has_many :cancelled_bookings, class_name: 'Booking', foreign_key: :cancelled_by_id, inverse_of: :cancelled_by, dependent: :nullify
  has_many :reviews_received, class_name: 'Review', foreign_key: :reviewee_id, inverse_of: :reviewee, dependent: :destroy
  has_many :reviews_written, class_name: 'Review', foreign_key: :reviewer_id, inverse_of: :reviewer, dependent: :destroy

  has_many :conversations, ->(user) { unscope(:where).where(sender: user).or(where(receiver: user)) }, inverse_of: :sender, dependent: :destroy

  validates :gender, inclusion: GENDER, allow_blank: true
  validates :car_make, :car_model, :car_color, length: { maximum: 40 }
  validates :car_plate, length: { maximum: 12 }
  validates :time_zone, inclusion: ActiveSupport::TimeZone.all.map(&:name)
  validates :vehicle_avg_consumption, numericality: { greater_than: 0, less_than: 10 }, presence: true

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

  def average_rating
    reviews_received.average(:rating)&.to_f&.round(1)
  end

  def reviews_count
    reviews_received.count
  end

  def vehicle_description
    [car_color, car_make, car_model].compact_blank.join(' ').presence
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

# frozen_string_literal: true

# A user flags a trip, a person or a review for the moderators.
class Report < ApplicationRecord
  REASONS = %w[unsafe_driving fake_or_scam harassment wrong_information no_show inappropriate other].freeze
  STATUSES = %w[open resolved dismissed].freeze
  TYPES = %w[Itinerary User Review].freeze

  belongs_to :reporter, class_name: 'User'
  belongs_to :resolved_by, class_name: 'User', optional: true
  belongs_to :reportable, polymorphic: true

  scope :open, -> { where(status: 'open') }
  scope :recent, -> { order(created_at: :desc) }

  validates :reason, inclusion: { in: REASONS }
  validates :status, inclusion: { in: STATUSES }
  validates :reportable_type, inclusion: { in: TYPES }
  validates :details, length: { maximum: 1000 }
  validate :not_a_self_report
  validate :one_open_report_per_reporter, on: :create

  def open?
    status == 'open'
  end

  def resolve!(by:, status:, note: nil)
    update!(status:, resolved_by: by, resolved_at: Time.current, resolution_note: note.presence)
  end

  def reportable_label
    case reportable
    when Itinerary then reportable.title
    when Review then I18n.t('reports.review_label', rating: reportable.rating, reviewer: reportable.reviewer)
    else reportable.to_s
    end
  end

  private

  def not_a_self_report
    owner = case reportable
            when Itinerary then reportable.user
            when User then reportable
            when Review then reportable.reviewer
            end
    errors.add(:base, :own_content) if owner && owner == reporter
  end

  def one_open_report_per_reporter
    errors.add(:base, :already_reported) if Report.open.exists?(reporter_id:, reportable_type:, reportable_id:)
  end
end

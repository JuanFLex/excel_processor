class UserSession < ApplicationRecord
  belongs_to :user

  SIGN_OUT_REASONS = %w[manual timeout orphaned forced].freeze

  validates :started_at, presence: true
  validates :sign_out_reason, inclusion: { in: SIGN_OUT_REASONS }, allow_nil: true

  scope :active,   -> { where(ended_at: nil) }
  scope :finished, -> { where.not(ended_at: nil) }
  scope :recent,   -> { order(started_at: :desc) }
  scope :in_range, ->(from, to) { where(started_at: from..to) }

  def close!(reason: 'manual', at: Time.current)
    return if ended_at.present?

    closing_time = [at, started_at].max

    update!(
      ended_at: closing_time,
      duration_seconds: (closing_time - started_at).to_i,
      sign_out_reason: reason
    )
  end

  def active?
    ended_at.nil?
  end

  def duration
    return (Time.current - started_at).to_i if active?
    duration_seconds
  end
end

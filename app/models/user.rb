class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  has_many :processed_files, dependent: :destroy
  has_many :user_sessions,   dependent: :destroy

  def total_files_processed
    processed_files.where(status: 'completed').count
  end

  def total_files_uploaded
    processed_files.count
  end

  def last_activity
    [last_sign_in_at,
     processed_files.maximum(:updated_at),
     user_sessions.maximum(:started_at)].compact.max
  end

  def current_session
    user_sessions.active.order(started_at: :desc).first
  end

  def average_session_duration
    user_sessions.finished.average(:duration_seconds)
  end

  def total_time_logged_in
    user_sessions.finished.sum(:duration_seconds)
  end
end

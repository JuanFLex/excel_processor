class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  has_many :processed_files, dependent: :destroy

  def total_files_processed
    processed_files.where(status: 'completed').count
  end

  def total_files_uploaded
    processed_files.count
  end

  def last_activity
    [last_sign_in_at, processed_files.maximum(:updated_at)].compact.max
  end

  def session_duration
    return nil unless current_sign_in_at && last_sign_in_at
    return nil if current_sign_in_at == last_sign_in_at
    
    (current_sign_in_at - last_sign_in_at) / 1.hour
  end
end

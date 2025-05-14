class ProcessedFile < ApplicationRecord
  has_many :processed_items, dependent: :destroy
  
  validates :original_filename, presence: true
  validates :status, presence: true, inclusion: { in: ['pending', 'processing', 'completed', 'failed'] }
  
  def completed?
    status == 'completed'
  end
  
  def failed?
    status == 'failed'
  end
  
  def pending?
    status == 'pending'
  end
  
  def processing?
    status == 'processing'
  end
end
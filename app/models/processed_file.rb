class ProcessedFile < ApplicationRecord
  has_one_attached :original_file
  has_many :processed_items, dependent: :destroy
  
  validates :original_filename, presence: true
  validates :status, presence: true, inclusion: { in: ['pending', 'queued', 'processing', 'completed', 'failed'] }
  
  
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

  def queued?
    status == 'queued'
  end

end
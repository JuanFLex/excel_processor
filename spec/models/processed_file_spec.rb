require 'rails_helper'

RSpec.describe ProcessedFile, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:original_filename) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(['pending', 'queued', 'processing', 'completed', 'failed']) }
  end
  
  describe 'associations' do
    it { should have_many(:processed_items).dependent(:destroy) }
  end
  
  describe 'status methods' do
    it 'returns true for completed? when status is completed' do
      processed_file = build(:processed_file, status: 'completed')
      expect(processed_file.completed?).to be true
    end
    
    it 'returns true for failed? when status is failed' do
      processed_file = build(:processed_file, status: 'failed')
      expect(processed_file.failed?).to be true
    end
    
    it 'returns true for pending? when status is pending' do
      processed_file = build(:processed_file, status: 'pending')
      expect(processed_file.pending?).to be true
    end
    
    it 'returns true for processing? when status is processing' do
      processed_file = build(:processed_file, status: 'processing')
      expect(processed_file.processing?).to be true
    end
    
    it 'returns true for queued? when status is queued' do
      processed_file = build(:processed_file, status: 'queued')
      expect(processed_file.queued?).to be true
    end
  end
end
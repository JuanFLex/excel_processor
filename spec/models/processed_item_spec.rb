require 'rails_helper'

RSpec.describe ProcessedItem, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:item) }
    it { should validate_presence_of(:description) }
    it { should validate_numericality_of(:std_cost).allow_nil }
    it { should validate_numericality_of(:last_purchase_price).allow_nil }
    it { should validate_numericality_of(:last_po).allow_nil }
    it { should validate_numericality_of(:eau).only_integer.allow_nil }
  end
  
  describe 'associations' do
    it { should belong_to(:processed_file) }
  end
end
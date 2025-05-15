require 'rails_helper'

RSpec.describe CommodityReference, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:level2_desc) }
  end
  
  describe '.find_most_similar' do
    before do
      @ref1 = create(:commodity_reference, level2_desc: 'Capacitors', embedding: [1.0, 0.0, 0.0])
      @ref2 = create(:commodity_reference, level2_desc: 'Resistors', embedding: [0.0, 1.0, 0.0])
      @ref3 = create(:commodity_reference, level2_desc: 'Inductors', embedding: [0.0, 0.0, 1.0])
    end
    
    it 'returns the most similar commodity based on embedding' do
      # Query embedding más cercano a Capacitors
      result = CommodityReference.find_most_similar([0.9, 0.1, 0.0])
      expect(result.first).to eq(@ref1)
      
      # Query embedding más cercano a Resistors
      result = CommodityReference.find_most_similar([0.1, 0.9, 0.0])
      expect(result.first).to eq(@ref2)
      
      # Query embedding más cercano a Inductors
      result = CommodityReference.find_most_similar([0.1, 0.1, 0.8])
      expect(result.first).to eq(@ref3)
    end
    
    it 'returns an empty array if embedding is nil' do
      result = CommodityReference.find_most_similar(nil)
      expect(result).to be_empty
    end
  end
end
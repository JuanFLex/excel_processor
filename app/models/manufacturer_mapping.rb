class ManufacturerMapping < ApplicationRecord
  validates :original_name, presence: true
  validates :standardized_name, presence: true
  
  # Estandarizar nombre de manufacturero
  def self.standardize(name)
    return name if name.blank?
    
    mapping = find_by(original_name: name.strip)
    mapping ? mapping.standardized_name : name
  end
end
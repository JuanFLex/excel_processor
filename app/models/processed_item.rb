class ProcessedItem < ApplicationRecord
  belongs_to :processed_file
  
  validates :item, presence: true
  validates :description, presence: true
  
  # Tipos de datos para los campos numéricos
  validates :std_cost, :last_purchase_price, :last_po, numericality: { allow_nil: true }
  validates :eau, numericality: { only_integer: true, allow_nil: true }

   # Método para obtener solo el valor EAR calculado
  def ear_value
    return nil if eau.blank? || eau <= 0
    
    prices = [std_cost, last_purchase_price, last_po].compact.select { |price| price > 0 }
    return nil if prices.empty?
    
    (prices.min * eau).round(2)
  end
  
  # Método para el status del threshold
  def ear_threshold_status
    value = ear_value
    return "Insufficient data" if value.nil?
    
    value >= 100_000 ? "Compliant" : "Non-Compliant"
  end
end
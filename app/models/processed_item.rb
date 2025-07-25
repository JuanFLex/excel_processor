class ProcessedItem < ApplicationRecord
  belongs_to :processed_file
  
  validates :item, presence: true
  validates :description, presence: true
  
  # Tipos de datos para los campos numéricos
  validates :std_cost, :last_purchase_price, :last_po, numericality: { allow_nil: true }
  validates :eau, numericality: { only_integer: true, allow_nil: true }

  def ear_threshold_status
    return "Insufficient data to calculate threshold" if eau.blank? || eau <= 0
    
    # Obtener valores válidos (no nil y mayor a 0) Nota: clean_monetary_value convierte datos inválidos a 0.0, así que excluimos 0
    prices = [std_cost, last_purchase_price, last_po].compact.select { |price| price > 0 }
    
    return "Insufficient data to calculate threshold" if prices.empty?
    
    min_price = prices.min
    total_value = min_price * eau
    
    total_value >= 100_000 ? "Exceeds threshold ($#{total_value.round(2)})" : "Below threshold ($#{total_value.round(2)})"
  end
end
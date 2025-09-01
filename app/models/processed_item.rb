class ProcessedItem < ApplicationRecord
  belongs_to :processed_file
  
  validates :item, presence: true
  validates :description, presence: true
  
  # Tipos de datos para los campos numéricos
  validates :std_cost, :last_purchase_price, :last_po, numericality: { allow_nil: true }
  validates :eau, numericality: { only_integer: true, allow_nil: true }

   # Método para obtener solo el valor EAR calculado
  def ear_value(total_demand = nil)
    # Primero intentar con EAU
    if eau.present? && eau > 0
      prices = [std_cost, last_purchase_price, last_po].compact.select { |price| price > 0 }
      return nil if prices.empty?
      return (prices.min * eau).round(2)
    end
    
    # Si no hay EAU, usar Total Demand
    if total_demand.present? && total_demand > 0
      prices = [std_cost, last_purchase_price, last_po].compact.select { |price| price > 0 }
      return nil if prices.empty?
      return (prices.min * total_demand).round(2)
    end
    
    nil
  end
  
  # Método para detectar si EAR usa Total Demand en lugar de EAU
  def ear_uses_total_demand?(total_demand = nil)
    (eau.blank? || eau <= 0) && total_demand.present? && total_demand > 0
  end
  
  # Método para el status del threshold
  def ear_threshold_status(total_demand = nil)
    value = ear_value(total_demand)
    return "Insufficient data" if value.nil?
    
    value >= 100_000 ? "Compliant" : "Non-Compliant"
  end
end
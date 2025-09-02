class ProcessedItem < ApplicationRecord
  belongs_to :processed_file
  
  validates :item, presence: true
  validates :description, presence: true
  
  # Tipos de datos para los campos numéricos
  validates :std_cost, :last_purchase_price, :last_po, numericality: { allow_nil: true }
  validates :eau, numericality: { only_integer: true, allow_nil: true }

   # Método para obtener solo el valor EAR calculado
  def ear_value(total_demand = nil, min_price = nil)
    # Primero intentar con EAU y precios originales
    if eau.present? && eau > 0
      prices = [std_cost, last_purchase_price, last_po].compact.select { |price| price > 0 }
      if prices.any?
        return (prices.min * eau).round(2)
      end
      # Si hay EAU pero no precios, usar min_price como fallback
      if min_price.present? && min_price > 0
        return (min_price * eau).round(2)
      end
    end
    
    # Si no hay EAU, usar Total Demand
    if total_demand.present? && total_demand > 0
      prices = [std_cost, last_purchase_price, last_po].compact.select { |price| price > 0 }
      if prices.any?
        return (prices.min * total_demand).round(2)
      end
      # Si hay Total Demand pero no precios, usar min_price como fallback
      if min_price.present? && min_price > 0
        return (min_price * total_demand).round(2)
      end
    end
    
    nil
  end
  
  # Método para detectar si EAR usa algún fallback (Total Demand o Min Price)
  def ear_uses_fallback?(total_demand = nil, min_price = nil)
    # Detecta si usa Total Demand (no hay EAU válido)
    uses_total_demand = (eau.blank? || eau <= 0) && total_demand.present? && total_demand > 0
    
    # Detecta si usa Min Price (hay demanda pero no precios originales)
    has_valid_demand = (eau.present? && eau > 0) || (total_demand.present? && total_demand > 0)
    has_original_prices = [std_cost, last_purchase_price, last_po].compact.any? { |price| price > 0 }
    uses_min_price = has_valid_demand && !has_original_prices && min_price.present? && min_price > 0
    
    uses_total_demand || uses_min_price
  end
  
  # Método para el status del threshold
  def ear_threshold_status(total_demand = nil, min_price = nil)
    value = ear_value(total_demand, min_price)
    return "Insufficient data" if value.nil?
    
    value >= ExcelProcessorConfig::EAR_THRESHOLD ? "Compliant" : "Non-Compliant"
  end
end
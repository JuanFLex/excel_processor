class ProcessedItem < ApplicationRecord
  belongs_to :processed_file
  
  validates :item, presence: true
  validates :description, presence: true
  
  # Tipos de datos para los campos numéricos
  validates :std_cost, :last_purchase_price, :last_po, numericality: { allow_nil: true }
  validates :eau, numericality: { only_integer: true, allow_nil: true }
end
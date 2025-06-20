class CommodityReferenceFilter
  # Lista de level3_desc específicos que deben ser excluidos
  EXCLUDED_LEVEL3 = [
    "Super Capacitor Module"
  ].freeze

  def self.should_skip?(row)
    level1 = row['LEVEL1_DESC']
    level3 = row['LEVEL3_DESC']
    
    # Skip referencias genéricas donde level1 == level3
    return true if level1 == level3
    
    # Skip level3_desc específicos excluidos
    return true if EXCLUDED_LEVEL3.include?(level3)
    
    false
  end
end
FactoryBot.define do
  factory :processed_item do
    association :processed_file
    
    sugar_id { "SG123456" }
    item { "CAP-001" }
    mfg_partno { "EEEFK1E101P" }
    global_mfg_name { "Panasonic" }
    description { "Capacitor 100µF 25V Aluminum" }
    site { "Warehouse A" }
    std_cost { 0.45 }
    last_purchase_price { 0.42 }
    last_po { 210.0 }
    eau { 5000 }
    commodity { "Capacitors" }
    scope { "In scope" }
    embedding { [0.1, 0.2, 0.3, 0.4, 0.5] }
  end
end
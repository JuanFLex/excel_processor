FactoryBot.define do
  factory :processed_item do
    processed_file { nil }
    sugar_id { "MyString" }
    item { "MyString" }
    mfg_partno { "MyString" }
    global_mfg_name { "MyString" }
    description { "MyText" }
    site { "MyString" }
    std_cost { "9.99" }
    last_purchase_price { "9.99" }
    last_po { "9.99" }
    eau { 1 }
    commodity { "MyString" }
    scope { "MyString" }
  end
end

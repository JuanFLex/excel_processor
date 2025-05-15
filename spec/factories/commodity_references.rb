FactoryBot.define do
  factory :commodity_reference do
    global_comm_code_desc { "Electronic Components" }
    level1_desc { "Passive Components" }
    level2_desc { "Capacitors" }
    level3_desc { "Ceramic Capacitors" }
    infinex_scope_status { "In Scope" }
    embedding { [0.1, 0.2, 0.3, 0.4, 0.5] }
  end
end

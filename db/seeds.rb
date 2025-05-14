require 'csv'

# Crear directorio para datos de ejemplo si no existe
FileUtils.mkdir_p(Rails.root.join('db', 'sample_data'))

# Crear archivo CSV de commodities de ejemplo
commodities_csv_path = Rails.root.join('db', 'sample_data', 'commodity_references.csv')

unless File.exist?(commodities_csv_path)
  CSV.open(commodities_csv_path, 'w') do |csv|
    # Encabezados
    csv << ['GLOBAL_COMM_CODE_DESC', 'LEVEL1_DESC', 'LEVEL2_DESC', 'LEVEL3_DESC', 'Infinex Scope Status']
    
    # Datos de ejemplo (se añadirán aquí)
    csv << ['Electronic Components', 'Passive Components', 'Capacitors', 'Ceramic Capacitors', 'In Scope']
    csv << ['Electronic Components', 'Passive Components', 'Capacitors', 'Tantalum Capacitors', 'In Scope']
    csv << ['Electronic Components', 'Passive Components', 'Resistors', 'Chip Resistors', 'In Scope']
    csv << ['Electronic Components', 'Passive Components', 'Inductors', 'Power Inductors', 'In Scope']
    csv << ['Electronic Components', 'Semiconductor', 'Microcontrollers', 'ARM Microcontrollers', 'In Scope']
    csv << ['Electronic Components', 'Semiconductor', 'Memory', 'DRAM', 'In Scope']
    csv << ['Electronic Components', 'Semiconductor', 'Memory', 'Flash', 'In Scope']
    csv << ['Electronic Components', 'Semiconductor', 'Logic', 'Gates', 'Out of Scope']
    csv << ['Electronic Components', 'Connectors', 'Board to Board', 'Headers', 'In Scope']
    csv << ['Electronic Components', 'Connectors', 'Wire to Board', 'Terminal Blocks', 'In Scope']
    csv << ['Electronic Components', 'Connectors', 'RF Connectors', 'SMA Connectors', 'Out of Scope']
    csv << ['Mechanical Components', 'Fasteners', 'Screws', 'Machine Screws', 'Out of Scope']
    csv << ['Mechanical Components', 'Fasteners', 'Nuts', 'Hex Nuts', 'Out of Scope']
    csv << ['Mechanical Components', 'Enclosures', 'Plastic Cases', 'IP65 Enclosures', 'In Scope']
    csv << ['Mechanical Components', 'Enclosures', 'Metal Cases', 'Aluminum Enclosures', 'In Scope']
    csv << ['Electromechanical', 'Switches', 'Tactile Switches', 'SMD Tactile Switches', 'In Scope']
    csv << ['Electromechanical', 'Switches', 'Toggle Switches', 'Panel Mount Switches', 'In Scope']
    csv << ['Electromechanical', 'Relays', 'Power Relays', 'Automotive Relays', 'Out of Scope']
    csv << ['Power', 'Power Supplies', 'AC-DC Converters', 'Open Frame PSU', 'In Scope']
    csv << ['Power', 'Power Supplies', 'DC-DC Converters', 'Isolated Converters', 'In Scope']
    csv << ['Power', 'Batteries', 'Lithium Ion', 'Cylindrical Cells', 'Out of Scope']
    csv << ['Power', 'Batteries', 'Lithium Polymer', 'Custom LiPo Packs', 'Out of Scope']
    csv << ['Sensors', 'Temperature Sensors', 'Thermistors', 'NTC Thermistors', 'In Scope']
    csv << ['Sensors', 'Pressure Sensors', 'MEMS Pressure Sensors', 'Absolute Pressure', 'In Scope']
    csv << ['Sensors', 'Motion Sensors', 'Accelerometers', '3-Axis MEMS', 'In Scope']
    csv << ['Sensors', 'Motion Sensors', 'Gyroscopes', 'MEMS Gyros', 'Out of Scope']
    csv << ['RF/Wireless', 'Antennas', 'PCB Antennas', 'Chip Antennas', 'In Scope']
    csv << ['RF/Wireless', 'RF Modules', 'Bluetooth Modules', 'BLE 5.0 Modules', 'In Scope']
    csv << ['RF/Wireless', 'RF Modules', 'WiFi Modules', '802.11ac Modules', 'In Scope']
    csv << ['RF/Wireless', 'RF ICs', 'RF Transceivers', 'Sub-GHz Transceivers', 'Out of Scope']
  end
  
  puts "Archivo de commodities de ejemplo creado en #{commodities_csv_path}"
end

# Cargar las referencias de commodities en la base de datos
if CommodityReference.count == 0 && File.exist?(commodities_csv_path)
  puts "Cargando referencias de commodities..."
  CommodityReferenceLoader.load_from_csv(commodities_csv_path)
  puts "Referencias de commodities cargadas: #{CommodityReference.count}"
else
  puts "Las referencias de commodities ya están cargadas o no se encontró el archivo."
end

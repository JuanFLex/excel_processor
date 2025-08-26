class DescriptionExpanderService
  
  def self.expand(text)
    new.expand(text)
  end
  
  def expand(text)
    return "" if text.blank?
    
    # PRE-PROCESAMIENTO
    expanded = text.dup
    
    # A) Decodifica entidades HTML
    expanded.gsub!(/&amp;/, '&')
    
    # B) Normaliza guiones tipográficos a ASCII
    expanded.gsub!(/[\u2013\u2014\u2212]/, '-')
    
    # C) Estandariza AC/DC y DC/DC a ASCII
    expanded.gsub!(/\b(?:AC[-\/\s]DC|AC\s+DC)\b/i, 'Alternating Current / Direct Current')
    expanded.gsub!(/\b(?:DC[-\/\s]DC|DC\s+DC)\b/i, 'Direct Current / Direct Current')
    
    # D) Reemplaza " & " por " and " como conjunción
    expanded.gsub!(/\s&\s/, ' and ')
    
    # REGLAS DE EXPANSIÓN (orden importa)
    
    # 1) Conectividad/placa
    expanded.gsub!(/\bI\/O\b/i, 'Input/Output')
    expanded.gsub!(/\bW[-\s]?TO[-\s]?B\b/i, 'Wire to Board')
    expanded.gsub!(/\bW[-\s]?TO[-\s]?W\b/i, 'Wire to Wire')
    expanded.gsub!(/\bLVDS\b/i, 'Low-Voltage Differential Signaling')
    expanded.gsub!(/\bSMT\b/i, 'Surface-Mount Technology')
    expanded.gsub!(/\bRJ45\b/i, 'RJ45 (8P8C Ethernet)')
    
    # 2) Potencia (además de normalización AC/DC)
    expanded.gsub!(/\bAC\s+INLET\b/i, 'Alternating Current Inlet')
    expanded.gsub!(/\bDC\s+POWER\s+JACK\b/i, 'Direct Current Power Jack')
    
    # 3) Materiales/dispositivos
    expanded.gsub!(/\bNTC\b/i, 'Negative Temperature Coefficient')
    expanded.gsub!(/\bPTC\b/i, 'Positive Temperature Coefficient')
    expanded.gsub!(/\bGAN\b/i, 'GaN (Gallium Nitride)')
    expanded.gsub!(/\bSIC\b/i, 'SiC (Silicon Carbide)')
    expanded.gsub!(/\bEV\b/i, 'Electric Vehicle')
    
    # 4) Tokens de lista (solo inicio de línea o tras coma+espacio)
    # CONN también se expande (CON seguido de N al inicio o tras coma)
    expanded.gsub!(/(^|,\s*)CONN?\b/i, '\1Connector')
    expanded.gsub!(/(^|,\s*)ASSY\b/i, '\1Assembly')
    expanded.gsub!(/(^|,\s*)PCB\b/i, '\1Printed Circuit Board')
    expanded.gsub!(/(^|,\s*)FPC\b/i, '\1Flexible Printed Circuit')
    expanded.gsub!(/(^|,\s*)HDI\b/i, '\1High-Density Interconnect')
    expanded.gsub!(/(^|,\s*)HDW\b/i, '\1Hardware')
    expanded.gsub!(/(^|,\s*)FAST\b/i, '\1Fasteners')
    expanded.gsub!(/(^|,\s*)MAG\b/i, '\1Magnetic')
    expanded.gsub!(/(^|,\s*)MECH\b/i, '\1Mechanical')
    
    # 5) Frequency Control & Oscillators
    expanded.gsub!(/(^|,\s*)FREQ\s+CTL\b/i, '\1Frequency Control')
    expanded.gsub!(/(^|,\s*)OSC\b/i, '\1Oscillators')
    # Solo expandir si NO está ya entre paréntesis (evita doble expansión)
    expanded.gsub!(/\bVCTCXO\b(?![^(]*\))/i, 'Voltage Controlled Temperature Compensated Crystal Oscillator (VCTCXO)')
    expanded.gsub!(/\bVCXO\b(?![^(]*\))/i, 'Voltage Controlled Crystal Oscillator (VCXO)')
    expanded.gsub!(/\bOCXO\b(?![^(]*\))/i, 'Oven Controlled Crystal Oscillator (OCXO)')
    expanded.gsub!(/\bTCXO\b(?![^(]*\))/i, 'Temperature Compensated Crystal Oscillator (TCXO)')
    
    # 6) Sensores (expansiones contextuales)
    # IC solo después de SENSOR (como palabra completa)
    expanded.gsub!(/\bSENSOR\s+IC\b/i, 'SENSOR Integrated Circuit')
    # Solo expandir MEMS si NO está ya entre paréntesis
    expanded.gsub!(/\bMEMS\b(?![^(]*\))/i, 'Micro-Electro-Mechanical Systems (MEMS)')
    
    expanded.strip
  end
  
  private
  
  # Método para verificar idempotencia (útil para testing)
  def self.verify_idempotent(text)
    first_expansion = expand(text)
    second_expansion = expand(first_expansion)
    first_expansion == second_expansion
  end
  
end
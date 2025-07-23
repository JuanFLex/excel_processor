# Configuración de Mocks para Diferentes Entornos

Este sistema permite trabajar con la aplicación en diferentes entornos donde no siempre tienes acceso a OpenAI o SQL Server.

## Quick Start

1. **Copia el archivo de configuración:**
```bash
cp .env.development.example .env.development
```

2. **Edita `.env.development` según tu entorno:**

### PC Trabajo (Red Corporativa)
```bash
# Sin acceso a OpenAI, con SQL Server
MOCK_OPENAI=true
```

### Servidor Producción  
```bash
# Con acceso completo - sin mocks
# (no definir variables o ponerlas en false)
```

### Desarrollo Local
```bash
# Con OpenAI, sin SQL Server  
MOCK_SQL_SERVER=true
OPENAI_API_KEY=tu_api_key
```

## Verificar que Funciona

### Test Básico
```bash
rails console
> OpenaiService.get_embedding_for_text("test")
# Debe mostrar 🎭 [MOCK OPENAI] si está mockeado
```

### Test de Cross-References
```bash
rails console  
> ItemLookup.lookup_by_supplier_pn("PKG-001")
# Debe mostrar 🎭 [MOCK SQL] si está mockeado
```

### Test Completo
```bash
# Subir un archivo Excel y verificar que procesa correctamente
rails server
# Ir a http://localhost:3000 y subir archivo
```

## Logs para Debugging

Los mocks generan logs distintivos:
- `🎭 [MOCK OPENAI]` - OpenAI está mockeado
- `🎭 [MOCK SQL]` - SQL Server está mockeado

## Datos de Prueba

### MockItemLookup incluye:
- `PKG-001`, `PKG-002` - Items de packaging
- `HW-001`, `BOLT-123` - Items de hardware  
- `MOTOR-123`, `RELAY-456` - Items eléctricos
- `TEST-001`, `CROSS-REF-PART` - Items de prueba

### MockOpenaiService:
- Genera embeddings determinísticos (mismo texto = mismo embedding)
- Mapeo inteligente de columnas basado en nombres comunes
- 1536 dimensiones como el servicio real

## Troubleshooting

**Error de conexión OpenAI:**
```bash
export MOCK_OPENAI=true
rails server
```

**Error de conexión SQL Server:**
```bash
export MOCK_SQL_SERVER=true  
rails server
```

**Combinar ambos:**
```bash
export MOCK_OPENAI=true
export MOCK_SQL_SERVER=true
rails server
```
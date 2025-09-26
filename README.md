# Excel Processor

**AI-powered Excel file standardization for commodity classification**

Transform unstructured Excel files into standardized formats with automatic column mapping and AI-driven commodity classification.

---

## What it does

**Input**: Non-standardized Excel files with varying column names and formats  
**Output**: Standardized Excel files with consistent schema and AI-classified commodities

### Core features

- **Automatic column detection** - Uses OpenAI to map your columns to standard fields
- **Smart commodity classification** - AI embeddings classify products into categories  
- **Level3 optimization** - If your file already has LEVEL3_DESC, only determines scope (saves tokens)
- **Automatic AI correction** - Analyzes and corrects commodity assignments for top EAR items
- **Remapping capability** - Adjust column mappings and commodity classifications
- **Asynchronous processing** - Upload and get notified when complete
- **Real-time status** - Watch processing progress
- **Export functionality** - Download processed files in multiple formats
- **PDF reports** - Generate detailed analysis reports
- **Admin controls** - File deletion and user management
- **Cross-reference lookup** - Integration with external SQL Server database
- **Pagination** - Handle large file lists efficiently

### Supported formats

- `.xlsx` (Excel 2007+)
- `.xls` (Excel 97-2003) 
- `.csv` (Comma-separated values)

---

## Quick start

### Prerequisites

- Ruby 3.2+
- PostgreSQL (for main database)
- SQL Server (for cross-reference lookups, optional with mock mode)
- OpenAI API key

### Installation

```bash
# Clone and setup
git clone 
cd excel-processor
bundle install

# Database setup
rails db:create db:migrate

# Configure credentials (required)
rails credentials:edit
# Add:
# openai:
#   api_key: your_openai_api_key
# sqlserver:
#   username: your_sql_username
#   password: your_sql_password

# Create database config (not tracked in git)
cp config/database.yml.example config/database.yml
# Edit config/database.yml with your database settings

# Optional: Enable mock mode for development
echo "MOCK_OPENAI=true" >> .env
echo "MOCK_SQL_SERVER=true" >> .env

# Start server
rails server
```

### Basic usage

1. **Upload commodity references** (one-time setup)
   - Go to `/commodity_references/upload`
   - Upload CSV with: `GLOBAL_COMM_CODE_DESC,LEVEL1_DESC,LEVEL2_DESC,LEVEL3_DESC,Infinex Scope Status`

2. **Process your Excel file**
   - Go to root URL
   - Upload your Excel/CSV file
   - Wait for processing (runs in background)

3. **Download results**
   - **Excel file**: Standardized data with AI-generated `Commodity` and `Scope` columns
   - **PDF report**: Detailed analysis and classification summary
   - **Export options**: Multiple format support for downstream processing

---

## How it works

### Standard output schema

Every processed file gets these columns:

| Column | Description | Type |
|--------|-------------|------|
| `SUGAR_ID` | Item identifier | String |
| `ITEM` | Item code | String |
| `MFG_PARTNO` | Manufacturer part number | String |
| `GLOBAL_MFG_NAME` | Manufacturer name | String |
| `DESCRIPTION` | Item description | Text |
| `SITE` | Location/facility | String |
| `STD_COST` | Standard cost | Number |
| `LAST_PURCHASE_PRICE` | Last purchase price | Number |
| `LAST_PO` | Last PO price | Number |
| `EAU` | Estimated Annual Usage | Integer |
| `Commodity` | **AI-generated classification** | String |
| `Scope` | **In scope / Out of scope** | String |

### Processing logic

1. **Column identification**: OpenAI analyzes your headers and maps them
2. **Commodity classification**:
   - If file has `LEVEL3_DESC` → use existing commodities, determine scope only
   - If no `LEVEL3_DESC` → generate embeddings and find similar commodities
3. **Scope determination**: Multi-tier logic determines "In scope" or "Out of scope"
4. **Cross-reference override**: Items with SQL Server cross-references become "In scope"
5. **Automatic correction**: AI analyzes top EAR items and corrects commodity assignments with high confidence
6. **Excel generation**: Create standardized output file

### Scope Determination Business Logic

The system uses a hierarchical approach to determine scope status:

#### 1. Base Scope Determination
- **Commercial Mode** (default): Uses `infinex_scope_status` from commodity references
- **Auto Mode** (when enabled): Uses `autograde_scope` from commodity references if present, falls back to `infinex_scope_status`

#### 2. Cross-Reference Override (Highest Priority)
- Any MPN found in SQL Server cross-reference database automatically becomes "In scope"
- **Important**: This override applies regardless of mode (Commercial or Auto)
- **Business Rule**: Cross-references indicate confirmed vendor relationships

#### 3. Mode-Specific Logic

**Commercial Mode:**
```
Scope = infinex_scope_status from commodity_references table
If cross-reference exists → Force "In scope"
```

**Auto Mode (include_medical_auto_grades = true):**
```
Scope = autograde_scope (if present) OR infinex_scope_status (fallback)
If cross-reference exists → Force "In scope"
```

#### 4. Fallback Rules
- **Unknown commodities**: Default to "Out of scope"
- **Missing scope data**: Default to "Out of scope"
- **Insufficient context**: Marked as "Requires Review"

#### 5. Priority Order (Highest to Lowest)
1. **Cross-reference override**: Always "In scope" if MPN exists in cross-reference database
2. **Auto Mode scope**: Uses `autograde_scope` when Auto Mode enabled
3. **Commercial scope**: Uses `infinex_scope_status` as default/fallback
4. **Default fallback**: "Out of scope" for unknown items

### AI optimization

- **Token savings**: Files with existing LEVEL3_DESC skip embedding generation
- **Batch processing**: Reduces API calls by processing items in groups
- **Embedding cache**: Avoids regenerating embeddings for similar descriptions
- **Automatic correction**: Improves accuracy by analyzing highest revenue items
- **Conservative corrections**: Only applies changes with high AI confidence
- **Smart fallbacks**: Handles unknown commodities gracefully

---

## Automatic AI Correction

The system automatically analyzes and corrects commodity assignments for items with the highest business impact:

### How it works

1. **Target identification**: After processing, identifies top items by Estimated Annual Revenue (EAR)
2. **AI analysis**: Uses same detailed analysis as manual review but returns structured JSON
3. **Conservative correction**: Only applies changes when AI has high confidence
4. **Background processing**: Runs automatically without user intervention

### Configuration

```ruby
# app/models/excel_processor_config.rb
TOP_EAR_ANALYSIS_COUNT = 1  # Number of top EAR items to analyze
```

### Correction criteria

- **High confidence required**: Only applies corrections with "high" confidence level
- **Evidence-based**: Analyzes MPN patterns, descriptions, and manufacturer data
- **Similarity matching**: Compares against top 5 most similar commodities
- **Conservative approach**: Prefers false negatives over false positives

### Logging

All automatic corrections are logged with details:
- Original vs. new commodity assignment
- AI confidence level and reasoning
- Evidence supporting the decision

---

## Remapping

Fix incorrect mappings without re-uploading:

1. **Access remap page** from processed file details
2. **Adjust column mappings** - Choose from all available source columns
3. **Change commodities** - Bulk update commodity classifications
4. **Reprocess** - Apply changes and get updated file

---

## Configuration

### Environment setup

```yaml
# config/credentials.yml.enc (encrypted, safe to commit)
openai:
  api_key: your_openai_api_key
sqlserver:
  username: your_sql_username  
  password: your_sql_password
```

```yaml
# config/database.yml (NOT tracked in git)
default: &default
  adapter: postgresql
  encoding: unicode
  username: your_pg_username
  password: your_pg_password
  host: localhost
```

```bash
# .env (optional, for development)
MOCK_OPENAI=true          # Use mock OpenAI responses
MOCK_SQL_SERVER=true      # Use mock SQL Server data
OPENAI_SSL_BYPASS=true    # Skip SSL verification if needed
```

### Models used

- `text-embedding-3-small` - For commodity similarity matching
- `gpt-4-turbo` - For column identification and analysis

### Performance tuning

```ruby
# config/environments/production.rb
config.active_job.queue_adapter = :async
```

---

## Testing

Simple integration tests that verify end-to-end functionality:

```bash
# Run tests
rails test

# Specific test files
rails test test/integration/file_upload_integration_test.rb
rails test test/integration/file_remap_integration_test.rb
```

Tests simulate OpenAI responses to avoid API costs and ensure reliability.

---

## Architecture decisions

### Technical decisions made

- **NO Redis** - Keep infrastructure simple, avoid external dependencies
- **NO Sidekiq** - Use Active Job with async adapter (Rails native)
- **NO Hotwire** - Maintain simplicity with traditional request/response
- **NO bundle exec** - Use bundle directly, ignore psych warnings
- **YES Active Storage** - Store original files for remapping capability
- **YES PostgreSQL** - JSONB support for embeddings and column mappings
- **YES Tailwind CSS** - Manual setup, no cssbundling-rails complexity
- **YES Kaminari** - Simple pagination without extra configuration

### Why these choices

- **Rails 7.1**: Mature, productive framework
- **PostgreSQL**: JSONB support for embeddings and metadata
- **Active Storage**: Built-in file handling
- **Active Job**: Async processing without external dependencies
- **Tailwind CSS**: Utility-first styling
- **No Redis/Sidekiq**: Keep infrastructure simple
- **No Hotwire**: Maintain simplicity with traditional requests

### OpenAI optimization decisions

- **Batch processing** - Process items in groups to reduce API calls
- **Embedding cache** - In-memory cache to avoid duplicate API requests
- **Character limits** - Truncate long descriptions to save tokens
- **LEVEL3_DESC detection** - Skip AI classification when exact commodity exists
- **Scope-only processing** - When commodities exist, only determine scope
- **Automatic correction** - Target highest EAR items for maximum business impact
- **High confidence threshold** - Only apply corrections with high AI certainty

### File processing flow

```
Upload → Active Storage → Background Job → OpenAI API → Database → Auto-Correction → Excel Generation
```

### Data storage

- **ProcessedFile**: Metadata, status, column mappings
- **ProcessedItem**: Individual row data with AI classifications  
- **CommodityReference**: Classification reference database

---

## Known limitations

- **Large files**: Processing time scales with file size and AI API latency
- **OpenAI dependency**: Requires internet connection and valid API key
- **Column variety**: Works best with recognizable English column names
- **Single tenant**: No multi-user/organization support

---

## Troubleshooting

### Common issues

**Processing fails immediately**
- Check OpenAI API key in credentials
- Verify file format is supported

**Commodity references missing**
- Upload reference CSV file first
- Ensure CSV has required columns

**Column mapping incorrect**
- Use remap functionality to adjust
- Ensure source columns have clear names

**Memory issues with large files**
- Increase server memory
- Process files in smaller batches

### Getting help

- Check logs: `tail -f log/development.log`
- Rails console: `rails console` → `ProcessedFile.last.status`
- Reset database: `rails db:reset`

---

## Contributing

This is a focused application for a specific use case. If you want to contribute:

1. Keep it simple - no over-engineering
2. Test your changes
3. Update documentation
4. Follow existing patterns

---

## License

MIT License - Use freely for commercial and personal projects.
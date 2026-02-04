# frozen_string_literal: true

# Configuration constants for Excel Processor
class ExcelProcessorConfig
  # Standard output columns for all processed files
  TARGET_COLUMNS = [
    'SFDC QUOTE NUMBER', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME',
    'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE',
    'LAST_PO', 'EAU'
  ].freeze

  # Processing constants
  BATCH_SIZE = 1000 # Items per batch for SQL Server queries
  EAR_THRESHOLD = 100_000 # Minimum EAR value for "Compliant" status
  
  # Performance constants
  MILLISECONDS_PER_SECOND = 1000
  MEMORY_ESTIMATION_FACTOR = 6.3 # Bytes per cache entry for memory calculation

  # Excel generation constants
  DEFAULT_COLUMN_WIDTHS = [15, 15, 20, 20, 30, 15, 15, 15, 15, 15, 15, 15, 20, 25, 15, 25, 15, 18, 20, 18, 15, 15].freeze
  
  # File processing
  MAX_SAMPLE_ROWS = 50 # Maximum rows to analyze for column mapping
  
  # OpenAI service constants
  EMBEDDINGS_CACHE_LIMIT = 1000 # Maximum cache entries before cleanup
  TEXT_TRUNCATION_LIMIT = 1000 # Maximum characters for OpenAI API calls
  
  # Automatic AI analysis constants
  TOP_EAR_ANALYSIS_COUNT = 10 # Number of top EAR items to analyze automatically
  SIMILARITY_ANALYSIS_LIMIT = 10 # Number of similar commodities to retrieve for analysis

  # Email configuration
  EMAIL_CONFIG = {
    opportunity_to: "lynn.moore@flexcoreworks.com",
    opportunity_cc: "linda.ramos@flex.com;Luis.Cortes@flex.com"
  }.freeze
  # UI settings
  COLUMN_PREVIEW_TIMER_SECONDS = 20
end
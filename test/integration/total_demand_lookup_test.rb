require 'test_helper'

class TotalDemandLookupTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  def setup
    # Clean up previous test data
    ProcessedFile.destroy_all
    CommodityReference.destroy_all
    User.destroy_all
    
    # Create test user and sign in
    @user = User.create!(email: 'test@test.com', password: 'password123')
    sign_in @user
    
    # Create test data
    create_test_commodity_references
  end

  test "ProcessedFile stores Total Demand lookup setting correctly" do
    # Test enabled setting
    processed_file_enabled = ProcessedFile.create!(
      original_filename: 'test_enabled.csv',
      status: 'pending',
      enable_total_demand_lookup: true
    )
    assert processed_file_enabled.enable_total_demand_lookup, "Should store enabled setting"
    
    # Test disabled setting (default)
    processed_file_disabled = ProcessedFile.create!(
      original_filename: 'test_disabled.csv',
      status: 'pending',
      enable_total_demand_lookup: false
    )
    assert_not processed_file_disabled.enable_total_demand_lookup, "Should store disabled setting"
  end

  test "ExcelProcessorService respects Total Demand lookup setting" do
    # Create a processed file with Total Demand lookup disabled
    processed_file = ProcessedFile.create!(
      original_filename: 'test.csv',
      status: 'processing',
      enable_total_demand_lookup: false
    )
    
    service = ExcelProcessorService.new(processed_file)
    
    # Test that lookup_total_demand returns nil when disabled
    result = service.send(:lookup_total_demand, 'TEST_ITEM')
    assert_nil result, "Should return nil when Total Demand lookup is disabled"
    
    # Enable Total Demand lookup
    processed_file.update!(enable_total_demand_lookup: true)
    service = ExcelProcessorService.new(processed_file)
    
    # With mock data, should return a value when enabled
    ENV['MOCK_SQL_SERVER'] = 'true'
    
    # Load the cache first (simulate what happens during processing)
    service.send(:load_aml_cache_for_items, ['PKG-001'])
    
    result = service.send(:lookup_total_demand, 'PKG-001')  # This item exists in mock data
    assert_not_nil result, "Should return a value when Total Demand lookup is enabled and item exists in mock data"
    assert_equal 50000, result, "Should return the correct Total Demand value from mock data"
  end

  private

  def create_test_csv_file
    file_path = Rails.root.join('tmp', 'test_upload.csv')
    File.open(file_path, 'w') do |file|
      file.write("Item,Description,Manufacturer,MPN,Price,Quantity\n")
      file.write("LEM_ITEM_001,Test Item 1,Test Mfg,TM001,10.50,100\n")
      file.write("LEM_ITEM_002,Test Item 2,Test Mfg,TM002,20.75,200\n")
    end
    file_path
  end

  def create_test_commodity_references
    CommodityReference.create!([
      {
        global_comm_code_desc: 'TEST_COMMODITY_001',
        level1_desc: 'Level 1',
        level2_desc: 'Level 2', 
        level3_desc: 'Level 3',
        infinex_scope_status: 'In Scope'
      }
    ])
  end
end
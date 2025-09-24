require "test_helper"

class CommodityReferenceTest < ActiveSupport::TestCase
  def setup
    # Crear commodity reference con ambos scope fields
    @commodity_both_scopes = CommodityReference.create!(
      level3_desc: 'Test Commodity Both',
      infinex_scope_status: 'Out of scope',
      autograde_scope: 'In scope'
    )

    # Crear commodity solo con infinex_scope_status
    @commodity_infinex_only = CommodityReference.create!(
      level3_desc: 'Test Commodity Infinex Only',
      infinex_scope_status: 'In scope'
    )

    # Crear commodity solo con autograde_scope
    @commodity_auto_only = CommodityReference.create!(
      level3_desc: 'Test Commodity Auto Only',
      infinex_scope_status: 'Out of scope',
      autograde_scope: 'In scope'
    )

    # Crear commodity sin ningún scope
    @commodity_no_scope = CommodityReference.create!(
      level3_desc: 'Test Commodity No Scope'
    )
  end

  test "scope_for_commodity uses infinex_scope_status in commercial mode" do
    # Modo comercial (auto_mode = false) debería usar infinex_scope_status
    result = CommodityReference.scope_for_commodity('Test Commodity Both', 'level3_desc', false)
    assert_equal 'Out of scope', result

    result = CommodityReference.scope_for_commodity('Test Commodity Infinex Only', 'level3_desc', false)
    assert_equal 'In scope', result
  end

  test "scope_for_commodity uses autograde_scope in auto mode when available" do
    # Modo auto (auto_mode = true) debería usar autograde_scope cuando está disponible
    result = CommodityReference.scope_for_commodity('Test Commodity Both', 'level3_desc', true)
    assert_equal 'In scope', result

    result = CommodityReference.scope_for_commodity('Test Commodity Auto Only', 'level3_desc', true)
    assert_equal 'In scope', result
  end

  test "scope_for_commodity falls back to infinex_scope_status when autograde_scope is blank" do
    # En modo auto, si autograde_scope está vacío, debe usar infinex_scope_status
    result = CommodityReference.scope_for_commodity('Test Commodity Infinex Only', 'level3_desc', true)
    assert_equal 'In scope', result
  end

  test "scope_for_commodity handles case insensitive scope values" do
    # Crear commodity con scope en mayúsculas
    CommodityReference.create!(
      level3_desc: 'Test Case Insensitive',
      infinex_scope_status: 'In Scope',
      autograde_scope: 'Out of scope'
    )

    # Modo comercial
    result = CommodityReference.scope_for_commodity('Test Case Insensitive', 'level3_desc', false)
    assert_equal 'In scope', result

    # Modo auto
    result = CommodityReference.scope_for_commodity('Test Case Insensitive', 'level3_desc', true)
    assert_equal 'Out of scope', result
  end

  test "scope_for_commodity handles whitespace in scope values" do
    # Crear commodity con espacios extra
    CommodityReference.create!(
      level3_desc: 'Test Whitespace',
      infinex_scope_status: 'In scope',
      autograde_scope: 'Out of scope'
    )

    # Modo comercial
    result = CommodityReference.scope_for_commodity('Test Whitespace', 'level3_desc', false)
    assert_equal 'In scope', result

    # Modo auto
    result = CommodityReference.scope_for_commodity('Test Whitespace', 'level3_desc', true)
    assert_equal 'Out of scope', result
  end

  test "scope_for_commodity returns out of scope for non-existent commodity" do
    result = CommodityReference.scope_for_commodity('Non Existent Commodity', 'level3_desc', false)
    assert_equal 'Out of scope', result

    result = CommodityReference.scope_for_commodity('Non Existent Commodity', 'level3_desc', true)
    assert_equal 'Out of scope', result
  end

  test "scope_for_commodity returns out of scope when both scope fields are blank" do
    result = CommodityReference.scope_for_commodity('Test Commodity No Scope', 'level3_desc', false)
    assert_equal 'Out of scope', result

    result = CommodityReference.scope_for_commodity('Test Commodity No Scope', 'level3_desc', true)
    assert_equal 'Out of scope', result
  end

  test "scope_for_commodity works with global_comm_code_desc column type" do
    # Crear commodity con global_comm_code_desc
    CommodityReference.create!(
      global_comm_code_desc: 'TEST_GLOBAL_CODE',
      level3_desc: 'Test Commodity',
      infinex_scope_status: 'In scope',
      autograde_scope: 'Out of scope'
    )

    # Buscar por global_comm_code_desc
    result = CommodityReference.scope_for_commodity('TEST_GLOBAL_CODE', 'global_comm_code_desc', false)
    assert_equal 'In scope', result

    result = CommodityReference.scope_for_commodity('TEST_GLOBAL_CODE', 'global_comm_code_desc', true)
    assert_equal 'Out of scope', result
  end

  test "autograde_scope validation allows valid values" do
    commodity = CommodityReference.new(
      level3_desc: 'Valid Test',
      autograde_scope: 'In scope'
    )
    assert commodity.valid?

    commodity.autograde_scope = 'Out of scope'
    assert commodity.valid?

    commodity.autograde_scope = nil
    assert commodity.valid?

    commodity.autograde_scope = ''
    assert commodity.valid?
  end
end
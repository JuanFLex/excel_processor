# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_09_17_150115) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "commodity_references", force: :cascade do |t|
    t.string "global_comm_code_desc"
    t.string "level1_desc"
    t.string "level2_desc"
    t.string "level3_desc"
    t.string "infinex_scope_status"
    t.jsonb "embedding"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "keyword"
    t.text "mfr"
    t.text "level3_desc_expanded"
    t.text "typical_mpn_by_manufacturer"
    t.index ["infinex_scope_status"], name: "index_commodity_references_on_infinex_scope_status"
    t.index ["level2_desc"], name: "index_commodity_references_on_level2_desc"
  end

  create_table "manufacturer_mappings", force: :cascade do |t|
    t.string "original_name", null: false
    t.string "standardized_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["original_name"], name: "index_manufacturer_mappings_on_original_name"
  end

  create_table "processed_files", force: :cascade do |t|
    t.string "original_filename"
    t.string "status"
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "column_mapping"
    t.string "result_file_path"
    t.text "error_message"
    t.integer "volume_multiplier"
    t.index ["status"], name: "index_processed_files_on_status"
  end

  create_table "processed_items", force: :cascade do |t|
    t.bigint "processed_file_id", null: false
    t.string "sugar_id"
    t.string "item"
    t.string "mfg_partno"
    t.string "global_mfg_name"
    t.text "description"
    t.string "site"
    t.decimal "std_cost"
    t.decimal "last_purchase_price"
    t.decimal "last_po"
    t.integer "eau"
    t.string "commodity"
    t.string "scope"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "embedding"
    t.index ["commodity"], name: "index_processed_items_on_commodity"
    t.index ["item"], name: "index_processed_items_on_item"
    t.index ["mfg_partno"], name: "index_processed_items_on_mfg_partno"
    t.index ["processed_file_id"], name: "index_processed_items_on_processed_file_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "processed_items", "processed_files"
end

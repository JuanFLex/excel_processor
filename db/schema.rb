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

ActiveRecord::Schema[7.1].define(version: 2025_05_14_185122) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "commodity_references", force: :cascade do |t|
    t.string "global_comm_code_desc"
    t.string "level1_desc"
    t.string "level2_desc"
    t.string "level3_desc"
    t.string "infinex_scope_status"
    t.jsonb "embedding"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["infinex_scope_status"], name: "index_commodity_references_on_infinex_scope_status"
    t.index ["level2_desc"], name: "index_commodity_references_on_level2_desc"
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

  add_foreign_key "processed_items", "processed_files"
end

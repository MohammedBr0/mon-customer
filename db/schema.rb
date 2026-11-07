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

ActiveRecord::Schema[7.1].define(version: 2026_11_07_190300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "postgis"

  create_table "bookings", force: :cascade do |t|
    t.bigint "itinerary_id", null: false
    t.bigint "passenger_id", null: false
    t.integer "seats", default: 1, null: false
    t.string "status", default: "pending", null: false
    t.text "note"
    t.datetime "decided_at"
    t.datetime "cancelled_at"
    t.bigint "cancelled_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "price_per_seat", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "fee_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.string "fee_charged_to", default: "passenger", null: false
    t.decimal "fare_total", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "fee_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "passenger_total", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "driver_payout", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["cancelled_by_id"], name: "index_bookings_on_cancelled_by_id"
    t.index ["itinerary_id", "passenger_id"], name: "index_bookings_one_active_per_passenger", unique: true, where: "((status)::text = ANY ((ARRAY['pending'::character varying, 'confirmed'::character varying])::text[]))"
    t.index ["itinerary_id"], name: "index_bookings_on_itinerary_id"
    t.index ["passenger_id"], name: "index_bookings_on_passenger_id"
    t.index ["status"], name: "index_bookings_on_status"
  end

  create_table "conversations", force: :cascade do |t|
    t.string "conversable_type"
    t.bigint "conversable_id"
    t.bigint "sender_id"
    t.bigint "receiver_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversable_type", "conversable_id"], name: "index_conversations_on_conversable_type_and_conversable_id"
    t.index ["receiver_id"], name: "index_conversations_on_receiver_id"
    t.index ["sender_id", "receiver_id", "conversable_type", "conversable_id"], name: "unique_index_for_sender", unique: true
    t.index ["sender_id"], name: "index_conversations_on_sender_id"
  end

  create_table "feedbacks", force: :cascade do |t|
    t.string "category", default: "bug"
    t.text "message"
    t.string "url"
    t.string "status", default: "normal"
    t.bigint "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["user_id"], name: "index_feedbacks_on_user_id"
  end

  create_table "itineraries", force: :cascade do |t|
    t.string "slug"
    t.string "description"
    t.integer "num_people"
    t.integer "fuel_cost", default: 0
    t.integer "tolls", default: 0
    t.boolean "daily", default: false
    t.boolean "pink", default: false
    t.boolean "pets_allowed", default: false
    t.boolean "round_trip", default: false
    t.boolean "smoking_allowed", default: false
    t.datetime "leave_date", precision: nil
    t.datetime "return_date", precision: nil
    t.string "driver_gender"
    t.boolean "verified", default: false
    t.string "start_address"
    t.string "end_address"
    t.string "overview_polyline"
    t.geography "start_location", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}
    t.geography "end_location", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}
    t.geography "via_waypoints", limit: {:srid=>4326, :type=>"multi_point", :geographic=>true}
    t.geography "overview_path", limit: {:srid=>4326, :type=>"line_string", :geographic=>true}
    t.boolean "avoid_highways", default: false
    t.boolean "avoid_tolls", default: false
    t.bigint "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "cancelled_at"
    t.decimal "price_per_seat", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["cancelled_at"], name: "index_itineraries_on_cancelled_at"
    t.index ["slug"], name: "index_itineraries_on_slug", unique: true
    t.index ["user_id"], name: "index_itineraries_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id"
    t.bigint "sender_id"
    t.text "body"
    t.datetime "read_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
  end

  create_table "platform_settings", force: :cascade do |t|
    t.decimal "fee_percent", precision: 5, scale: 2, default: "10.0", null: false
    t.string "fee_charged_to", default: "passenger", null: false
    t.string "currency_code", default: "ETB", null: false
    t.string "currency_symbol", default: "Br", null: false
    t.decimal "max_price_per_seat", precision: 10, scale: 2, default: "10000.0", null: false
    t.text "payment_instructions"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "reviewer_id", null: false
    t.bigint "reviewee_id", null: false
    t.integer "rating", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id", "reviewer_id"], name: "index_reviews_on_booking_id_and_reviewer_id", unique: true
    t.index ["booking_id"], name: "index_reviews_on_booking_id"
    t.index ["reviewee_id"], name: "index_reviews_on_reviewee_id"
    t.index ["reviewer_id"], name: "index_reviews_on_reviewer_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "bio"
    t.date "birthday"
    t.string "gender"
    t.string "image"
    t.jsonb "languages", default: [], array: true
    t.string "name"
    t.string "locale"
    t.boolean "send_email_messages", default: false
    t.string "telephone"
    t.string "time_zone", default: "Nairobi"
    t.decimal "vehicle_avg_consumption", precision: 5, scale: 2, default: "8.0"
    t.boolean "admin", default: false
    t.boolean "banned", default: false
    t.string "access_token"
    t.datetime "access_token_expires_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "car_make"
    t.string "car_model"
    t.string "car_color"
    t.string "car_plate"
    t.jsonb "vehicle_data", default: {}, null: false
    t.string "phone"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  create_table "vehicle_fields", force: :cascade do |t|
    t.string "key", null: false
    t.string "label", null: false
    t.jsonb "labels", default: {}, null: false
    t.string "field_type", default: "text", null: false
    t.jsonb "options", default: [], null: false
    t.boolean "required", default: false, null: false
    t.string "visibility", default: "public", null: false
    t.string "help_text"
    t.integer "min_value"
    t.integer "max_value"
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_vehicle_fields_on_key", unique: true
  end

  add_foreign_key "bookings", "itineraries"
  add_foreign_key "bookings", "users", column: "cancelled_by_id"
  add_foreign_key "bookings", "users", column: "passenger_id"
  add_foreign_key "feedbacks", "users"
  add_foreign_key "itineraries", "users"
  add_foreign_key "reviews", "bookings"
  add_foreign_key "reviews", "users", column: "reviewee_id"
  add_foreign_key "reviews", "users", column: "reviewer_id"
end

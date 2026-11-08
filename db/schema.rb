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

ActiveRecord::Schema[7.1].define(version: 2026_11_08_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "postgis"

  create_table "api_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.string "device_name"
    t.datetime "last_used_at"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "action", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.string "subject_label"
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["subject_type", "subject_id"], name: "index_audit_logs_on_subject_type_and_subject_id"
  end

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
    t.date "ride_dates", default: [], null: false, array: true
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
    t.integer "commute_days", default: [], null: false, array: true
    t.date "commute_until"
    t.string "pickup_point"
    t.string "dropoff_point"
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

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "id"], name: "index_notifications_on_user_id_and_id"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
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
    t.text "announcement"
    t.boolean "announcement_active", default: false, null: false
    t.boolean "commutes_enabled", default: true, null: false
    t.integer "commute_horizon_days", default: 14, null: false
  end

  create_table "popular_routes", force: :cascade do |t|
    t.string "from_label", null: false
    t.string "to_label", null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reports", force: :cascade do |t|
    t.bigint "reporter_id", null: false
    t.string "reportable_type", null: false
    t.bigint "reportable_id", null: false
    t.string "reason", null: false
    t.text "details"
    t.string "status", default: "open", null: false
    t.bigint "resolved_by_id"
    t.datetime "resolved_at"
    t.text "resolution_note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reportable_type", "reportable_id"], name: "index_reports_on_reportable_type_and_reportable_id"
    t.index ["reporter_id"], name: "index_reports_on_reporter_id"
    t.index ["resolved_by_id"], name: "index_reports_on_resolved_by_id"
    t.index ["status"], name: "index_reports_on_status"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "reviewer_id", null: false
    t.bigint "reviewee_id", null: false
    t.integer "rating", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "hidden_at"
    t.index ["booking_id", "reviewer_id"], name: "index_reviews_on_booking_id_and_reviewer_id", unique: true
    t.index ["booking_id"], name: "index_reviews_on_booking_id"
    t.index ["reviewee_id"], name: "index_reviews_on_reviewee_id"
    t.index ["reviewer_id"], name: "index_reviews_on_reviewer_id"
  end

  create_table "ride_alerts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "start_label", null: false
    t.string "end_label", null: false
    t.geography "start_location", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}, null: false
    t.geography "end_location", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "last_notified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_ride_alerts_on_user_id"
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
    t.boolean "moderator", default: false, null: false
    t.datetime "verified_at"
    t.bigint "verified_by_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["verified_by_id"], name: "index_users_on_verified_by_id"
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

  add_foreign_key "api_tokens", "users"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "bookings", "itineraries"
  add_foreign_key "bookings", "users", column: "cancelled_by_id"
  add_foreign_key "bookings", "users", column: "passenger_id"
  add_foreign_key "feedbacks", "users"
  add_foreign_key "itineraries", "users"
  add_foreign_key "notifications", "users", on_delete: :cascade
  add_foreign_key "reports", "users", column: "reporter_id"
  add_foreign_key "reports", "users", column: "resolved_by_id"
  add_foreign_key "reviews", "bookings"
  add_foreign_key "reviews", "users", column: "reviewee_id"
  add_foreign_key "reviews", "users", column: "reviewer_id"
  add_foreign_key "ride_alerts", "users"
  add_foreign_key "users", "users", column: "verified_by_id"
end

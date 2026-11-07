# frozen_string_literal: true

class AddAdminTools < ActiveRecord::Migration[7.1]
  def change
    change_table :users, bulk: true do |t|
      t.boolean :moderator, null: false, default: false
      t.datetime :verified_at
      t.references :verified_by, foreign_key: { to_table: :users }
    end

    add_column :reviews, :hidden_at, :datetime

    change_table :platform_settings, bulk: true do |t|
      t.text :announcement
      t.boolean :announcement_active, null: false, default: false
      t.boolean :commutes_enabled, null: false, default: true
      t.integer :commute_horizon_days, null: false, default: 14
    end

    create_table :reports do |t|
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.string :reportable_type, null: false
      t.bigint :reportable_id, null: false
      t.string :reason, null: false
      t.text :details
      t.string :status, null: false, default: 'open'
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.text :resolution_note
      t.timestamps
    end
    add_index :reports, %i[reportable_type reportable_id]
    add_index :reports, :status

    create_table :audit_logs do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.string :subject_label
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :audit_logs, :action
    add_index :audit_logs, %i[subject_type subject_id]

    create_table :popular_routes do |t|
      t.string :from_label, null: false
      t.string :to_label, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
  end
end

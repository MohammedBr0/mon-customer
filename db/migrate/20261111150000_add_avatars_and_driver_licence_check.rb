# frozen_string_literal: true

class AddAvatarsAndDriverLicenceCheck < ActiveRecord::Migration[7.1]
  def change
    # Profile photos people upload from the app, kept apart from the users table so lists stay light.
    create_table :avatars do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.binary :image, null: false
      t.string :content_type, null: false
      t.timestamps
    end
  end
end

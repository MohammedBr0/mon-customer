# frozen_string_literal: true

class CreatePaymentMethodsAndIdentityDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_methods do |t|
      t.string :name, null: false
      t.string :name_am
      t.string :account_label # what the driver is asked for, e.g. "Telebirr number"; blank when nothing is needed (cash)
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :driver_payment_methods do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :payment_method, null: false, foreign_key: { on_delete: :cascade }
      t.string :account_name
      t.string :account_number
      t.timestamps
    end
    add_index :driver_payment_methods, %i[user_id payment_method_id], unique: true

    create_table :identity_documents do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :number
      t.binary :image, null: false
      t.string :content_type, null: false
      t.string :status, null: false, default: 'pending'
      t.string :rejection_reason
      t.references :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :identity_documents, %i[user_id kind], unique: true
    add_index :identity_documents, :status

    reversible do |direction|
      direction.up do
        now = Time.current.utc.strftime('%Y-%m-%d %H:%M:%S')
        [['Cash', 'ጥሬ ገንዘብ', nil], ['Telebirr', 'ቴሌብር', 'Telebirr number'], ['CBE Birr', 'ሲቢኢ ብር', 'CBE Birr number'], ['Bank transfer', 'የባንክ ዝውውር', 'Bank and account number']].each_with_index do |(name, am, label), index|
          execute "INSERT INTO payment_methods (name, name_am, account_label, active, position, created_at, updated_at) VALUES (#{quote(name)}, #{quote(am)}, #{label ? quote(label) : 'NULL'}, TRUE, #{index}, '#{now}', '#{now}')"
        end
      end
    end
  end
end

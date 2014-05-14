class CreateUsers < ActiveRecord::Migration
  def self.change
    create_table :users do |t|
      t.string :email_address, null: false, unique: true
      t.string :password, null: false
      t.timestamps
    end

    add_index :users, :email_address, unique: true
  end
end

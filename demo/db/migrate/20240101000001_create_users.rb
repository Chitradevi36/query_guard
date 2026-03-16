class CreateUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :users do |t|
      t.string :email
      t.string :name
      t.string :phone
      t.text :bio
      t.datetime :last_login_at
      t.integer :login_count, default: 0

      t.timestamps
    end
  end
end

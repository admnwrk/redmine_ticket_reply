class CreateTicketReplyContacts < ActiveRecord::Migration[5.2]
  def change
    create_table :ticket_reply_contacts do |t|
      t.integer  :issue_id,    null: false
      t.string   :mail_from
      t.text     :mail_to
      t.text     :mail_cc
      t.datetime :source_date
      t.timestamps
    end
    add_index :ticket_reply_contacts, :issue_id, unique: true
  end
end

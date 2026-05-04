class AddUserToProcessedFiles < ActiveRecord::Migration[7.1]
  def change
    add_reference :processed_files, :user, null: true, foreign_key: true
    
    # For existing records, set to first user if any exists
    # In production, you might want to handle this differently
    reversible do |dir|
      dir.up do
        if User.exists? && ProcessedFile.exists?
          first_user = User.first
          ProcessedFile.update_all(user_id: first_user.id)
        end
      end
    end
  end
end

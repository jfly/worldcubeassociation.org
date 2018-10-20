class AddWcat < ActiveRecord::Migration[5.2]
  def change
    execute <<-SQL
      INSERT INTO teams (friendly_id, email, rank, created_at, updated_at) values ('wcat', '<<<@worldcubeassociation.org', 110, NOW(), NOW());
    SQL
  end
end

# frozen_string_literal: true

require "active_record"

# In-memory SQLite database for fixture_kit tests
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :widgets, force: true do |t|
    t.string :name
    t.integer :quantity
  end
end

class Widget < ActiveRecord::Base
end

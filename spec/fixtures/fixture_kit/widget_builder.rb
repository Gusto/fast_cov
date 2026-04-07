# frozen_string_literal: true

module WidgetBuilder
  def self.build_special
    Widget.create!(name: "Special", quantity: 99)
  end
end

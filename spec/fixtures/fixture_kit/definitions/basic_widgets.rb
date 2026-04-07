# frozen_string_literal: true

require_relative "../widget_helper"

FixtureKit.define do
  widget = Widget.create!(name: WidgetHelper.default_name, quantity: WidgetHelper.default_quantity)
  expose(widget: widget)
end

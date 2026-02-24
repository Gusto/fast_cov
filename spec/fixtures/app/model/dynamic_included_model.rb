# frozen_string_literal: true

require_relative "../concerns/queryable"

module ModuleHolder
  INCLUDED = Object.const_get("Queryable")
end

class DynamicIncludedModel
  include ModuleHolder::INCLUDED
end

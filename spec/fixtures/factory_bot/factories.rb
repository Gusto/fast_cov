# frozen_string_literal: true

# Simple model classes for factory_bot tests
class User
  attr_accessor :name, :email

  def initialize(name: nil, email: nil)
    @name = name
    @email = email
  end
end

class Post
  attr_accessor :title, :body, :author

  def initialize(title: nil, body: nil, author: nil)
    @title = title
    @body = body
    @author = author
  end
end

FactoryBot.define do
  factory :user do
    name { "John Doe" }
    email { "john@example.com" }
  end

  factory :post do
    title { "Hello World" }
    body { "This is a post" }
    association :author, factory: :user
  end
end

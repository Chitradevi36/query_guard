# User model with SELECT * and N+1 query anti-pattern
class User < ApplicationRecord
  has_many :posts
  has_many :comments

  # ⚠️  ANTI-PATTERN: SELECT * without specific columns
  # This loads all columns including potentially large text fields
  scope :all_users_with_all_fields, -> { select('*').order(:created_at) }

  # ⚠️  ANTI-PATTERN: N+1 query
  # This will query each user's posts separately
  def recent_posts_count
    # Instead of:
    #   User.left_joins(:posts).select('users.*, COUNT(posts.id) as posts_count')
    # This does one query per user:
    posts.count
  end

  # ⚠️  ANTI-PATTERN: Unbounded query
  # Loading all posts without limit or pagination
  def all_posts_for_display
    posts
  end
end

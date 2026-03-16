# Post model with query anti-patterns
class Post < ApplicationRecord
  belongs_to :user
  has_many :comments

  # ⚠️  ANTI-PATTERN: Unindexed query on large table
  # If there are millions of posts, this query will be slow
  # without an index on :published_at
  scope :published, -> { where(published: true) }

  # ⚠️  ANTI-PATTERN: SELECT * on every related query
  # Loading all columns including large content field
  def display_with_full_details
    # Better:
    # Post.select('posts.id, posts.title, posts.view_count').find(id)
    self
  end

  # ⚠️  ANTI-PATTERN: Multiple 1+N queries
  def get_post_summary
    {
      title: title,
      author: user.name,         # +1 query to get user
      comment_count: comments.count,  # +1 query to count comments
      latest_comment: comments.last   # +1 query to get last comment
    }
  end
end

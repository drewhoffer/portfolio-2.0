class PostsController < ApplicationController
  def index
    @posts = [File.read(Rails.root.join("posts", "my_first_post.html.md"))]
  end

  def show

  end

end

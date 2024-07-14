class PostsController < ApplicationController
  before_action :set_post, only: [:show]
  def index
    # Read all files located in the `posts` directory and loop through calling the `extract_frontmatter` method
    @posts = Dir.entries(Rails.root.join("posts")).select { |f| f.end_with?(".html.md") }.map do |file|
      extract_frontmatter(file)
    end
  end

  def show

  end

  private

  def extract_frontmatter(file)
    parsed = FrontMatterParser::Parser.parse_file(
      Rails.root.join("posts", file),
      loader: FrontMatterParser::Loader::Yaml.new(allowlist_classes: [ Date ])
    )
    {
      **parsed.front_matter.transform_keys(&:to_sym),
      content: parsed.content,
      # Parse tags if present
      tags: parsed.front_matter["tags"].present? ? parsed.front_matter["tags"].split(",") : []
    }
  end


  def set_post
    # Find the file with the same slug as the one passed in the URL
    file = Dir.entries(Rails.root.join("posts")).find { |f| f.end_with?(".html.md") && extract_frontmatter(f)[:slug] == params[:id] }
    @post = extract_frontmatter(file)
  end

end

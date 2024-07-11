class PostsController < ApplicationController
  before_action :set_post, only: [:show]
  def index
    # Read all files located in the `posts` directory and loop through calling the `extract_frontmatter` method
    @posts = Dir.entries(Rails.root.join("posts")).select { |f| f.end_with?(".html.md") }.map do |file|
      front_matter = extract_frontmatter(file)
      {
        title: front_matter["title"],
        date: front_matter["date"],
        author: front_matter["author"],
        slug: front_matter["slug"]
      }
    end
  end

  def show

  end

  private

  def extract_frontmatter(file)
    return FrontMatterParser::Parser.parse_file(
      Rails.root.join("posts", file),
      loader: FrontMatterParser::Loader::Yaml.new(allowlist_classes: [ Date ])
    )
  end


  def set_post
    # Find the file with the same slug as the one passed in the URL
    puts params[:slug]
    file = Dir.entries(Rails.root.join("posts")).find { |f| f.end_with?(".html.md") && extract_frontmatter(f)["slug"] == params[:id] }
    # Call the `extract_frontmatter` method to parse the front matter
   front_matter = extract_frontmatter(file)
    {
      title: front_matter["title"],
      date: front_matter["date"],
      author: front_matter["author"],
      slug: front_matter["slug"]
    }
    # Render the file content as HTML
    @post = front_matter
    @post[:content] = Markdown.new(file).to_html.html_safe
    puts "#{@post}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
  end

end

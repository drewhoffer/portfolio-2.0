module ApplicationHelper
  def markdown(text)
    options = %i[
      underline
      quote
      hardwrap
      autolink
      fenced_code_blocks: true
    ]
    Markdown.new(text, options).to_html.html_safe
  end
end

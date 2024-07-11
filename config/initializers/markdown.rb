# We define a module that can parse markdown to HTML with its `call` method
module MarkdownHandler
  def self.erb
    @erb ||= ActionView::Template.registered_template_handler(:erb)
  end

  def self.call(template, source)
    parsed = FrontMatterParser::Parser.new(
      :md,
      loader: FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
    ).call(source.to_str)
    compiled_source = ActionView::OutputBuffer.new(erb.call(template, parsed.content))
    compiled_source << '.to_s'
    "Redcarpet::Markdown.new(Redcarpet::Render::HTML.new, fenced_code_blocks: true).render(begin;#{compiled_source};end).html_safe"
  end
end

# Now we tell Rails to process any files with the `.md` extension using our new MarkdownHandler
ActionView::Template.register_template_handler :md, MarkdownHandler

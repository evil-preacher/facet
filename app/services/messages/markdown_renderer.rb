module Messages
  class MarkdownRenderer
    class Renderer < Redcarpet::Render::HTML
      def image(_link, _title, alt_text)
        ERB::Util.html_escape(alt_text)
      end
    end

    ALLOWED_TAGS = %w[
      a blockquote br code del em h1 h2 h3 h4 h5 h6 hr li ol p pre strong table
      tbody td th thead tr ul
    ].freeze
    ALLOWED_ATTRIBUTES = %w[href].freeze

    RENDERER_OPTIONS = {
      filter_html: true,
      hard_wrap: true,
      safe_links_only: true
    }.freeze
    MARKDOWN_EXTENSIONS = {
      autolink: true,
      fenced_code_blocks: true,
      no_intra_emphasis: true,
      strikethrough: true,
      tables: true
    }.freeze
    SANITIZER = Rails::HTML5::SafeListSanitizer.new

    def self.call(content)
      rendered = Redcarpet::Markdown.new(
        Renderer.new(RENDERER_OPTIONS),
        MARKDOWN_EXTENSIONS
      ).render(content.to_s)
      SANITIZER.sanitize(rendered, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
    end
  end
end

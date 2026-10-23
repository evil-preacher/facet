require "rails_helper"

RSpec.describe Messages::MarkdownRenderer do
  it "renders common chat Markdown" do
    html = described_class.call("**Important**\n\n- one\n- two\n\n`code`")

    expect(html).to include("<strong>Important</strong>", "<ul>", "<li>one</li>", "<code>code</code>")
  end

  it "removes raw HTML, images, and unsafe links" do
    html = described_class.call(
      '<script>alert("xss")</script> ![secret](https://example.com/a.png) ' \
        '[click](javascript:alert("xss"))'
    )

    expect(html).to include("secret")
    expect(html).not_to include("<script", "<img", 'href="javascript:')
  end
end

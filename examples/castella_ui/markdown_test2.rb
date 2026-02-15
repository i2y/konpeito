# Test: short markdown WITH mermaid block

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

PART1 = "# Markdown Demo\n\nThis is a **Castella UI** markdown widget.\n\n## Text Formatting\n\nYou can use **bold text** and *italic text*.\n\nInline code: `hello()`\n\n## Code Block\n\n```ruby\ndef fibonacci(n)\n  return n\nend\n```\n\n## Lists\n\n- First item\n- Second item\n- Third item\n\n1. Step one\n2. Step two\n\n## Links\n\nVisit [Konpeito](https://example.com) for more.\n\n## Tables\n\n| Feature | Status |\n|---------|--------|\n| Bold | Done |\n| Tables | New |\n\n## Blockquote\n\n> This is a blockquote.\n\n---\n\n"

PART2 = "## Mermaid Flowchart\n\n```mermaid\ngraph TD\n    A[Start] --> B{Is it working?}\n    B -->|Yes| C[Great!]\n    B -->|No| D[Debug]\n    D --> B\n    C --> E[Done]\n```\n\n## Horizontal Flowchart\n\n```mermaid\ngraph LR\n    Input[User Input] --> Parse(Parse Request)\n    Parse --> Validate{Valid?}\n    Validate -->|Yes| Process[Process Data]\n    Validate -->|No| Error[Show Error]\n    Process --> Output[Return Result]\n```\n\nThat concludes the demo!"

SAMPLE_MARKDOWN = PART1 + PART2

class MarkdownTest2 < Component
  def view
    Column(
      Markdown(SAMPLE_MARKDOWN)
    ).scrollable
  end
end

frame = JWMFrame.new("Markdown Test", 700, 800)
app = App.new(frame, MarkdownTest2.new)
app.run

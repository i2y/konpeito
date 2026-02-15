# Markdown demo WITHOUT mermaid - to test if base still works

require_relative "../../lib/konpeito/ui/castella"

$theme = Theme.new

TEST_MD = "# Test

Hello **world**!

## Code

```ruby
puts 42
```

Done!"

class NoMermaidDemo < Component
  def view
    Column(
      Markdown(TEST_MD)
    ).scrollable
  end
end

frame = JWMFrame.new("No Mermaid", 600, 500)
app = App.new(frame, NoMermaidDemo.new)
app.run

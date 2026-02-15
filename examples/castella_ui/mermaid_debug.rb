# Minimal mermaid debug - test if parser + renderer work

require_relative "../../lib/konpeito/ui/castella"

# Global theme
$theme = Theme.new

# Ultra simple markdown - just a heading and mermaid
SIMPLE_MD = "# Mermaid Test

```mermaid
graph TD
    A[Start] --> B[End]
```

Done!"

class MermaidDebug < Component
  def view
    Column(
      Markdown(SIMPLE_MD)
    ).scrollable
  end
end

frame = JWMFrame.new("Mermaid Debug", 600, 500)
app = App.new(frame, MermaidDebug.new)
app.run

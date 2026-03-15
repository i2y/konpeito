# KUI Markdown Demo
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_markdown/md_demo \
#     examples/kui_markdown/md_demo.rb
#
# Run:
#   ./examples/kui_markdown/md_demo
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

#: () -> Integer
def draw
  scroll_panel(pad: 16, gap: 0) do
    markdown("# KUI Markdown Demo\n\n## Text Formatting\n\nA paragraph with **bold**, *italic*, and ***bold italic*** text.\n\nUse `inline code` and ~~strikethrough~~ too.\n\n## Code Block\n\n```\ndef hello\n  puts 42\nend\n```\n\n## Lists\n\n- First item\n- Second item\n  - Nested item\n- Third item\n\n1. Step one\n2. Step two\n3. Step three\n\n- [x] Done task\n- [ ] Todo task\n\n## Blockquote\n\n> This is a blockquote.\n> Second line.\n\n## Table\n\n| Name | Status |\n|------|--------|\n| Alpha | Done |\n| Beta | WIP |\n\n---\n\n*End of demo*\n", size: 16)
  end
  return 0
end

#: () -> Integer
def main
  kui_init("Markdown Demo", 800, 700)
  kui_load_font("/System/Library/Fonts/SFNS.ttf", 20)
  kui_theme_dark

  while kui_running == 1
    kui_begin_frame
    draw
    kui_end_frame
  end

  kui_destroy
  return 0
end

main

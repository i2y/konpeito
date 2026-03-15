# KUI Markdown Demo — TUI version (ClayTUI + termbox2)
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_markdown/md_demo_tui \
#     examples/kui_markdown/md_demo_tui.rb
#
# Run:
#   ./examples/kui_markdown/md_demo_tui
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_tui"

#: () -> Integer
def draw
  vpanel pad: 1, gap: 0 do
    markdown("# Markdown TUI Demo\n\n## Text Formatting\n\nA paragraph with **bold**, *italic*, and ***bold italic*** text.\n\nUse `inline code` and ~~strikethrough~~ too.\n\n## Code Block\n\n```\ndef hello\n  puts 42\nend\n```\n\n## Lists\n\n- First item\n- Second item\n  - Nested item\n- Third item\n\n1. Step one\n2. Step two\n\n- [x] Done task\n- [ ] Todo task\n\n## Blockquote\n\n> This is a blockquote.\n\n## Table\n\n| Name | Status |\n|------|--------|\n| Alpha | Done |\n| Beta | WIP |\n\n---\n\n*End of demo — press ESC to quit*\n", size: 1)
  end
  return 0
end

#: () -> Integer
def main
  kui_init("Markdown TUI", 80, 24)
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

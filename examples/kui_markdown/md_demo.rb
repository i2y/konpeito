# KUI Markdown Demo + IME Input Test
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_markdown/md_demo \
#     examples/kui_markdown/md_demo.rb
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

#: () -> Integer
def draw
  vpanel pad: 16, gap: 8 do
    label "Type below (IME supported):", size: 18
    text_input(0, w: 60, size: 18)
    divider
    markdown("# Markdown Demo\n\nA paragraph with **bold**, *italic*, and `code`.\n\n- Item one\n- Item two\n\n> Blockquote\n\n---\n\n*fin*\n", size: 16)
  end
  return 0
end

#: () -> Integer
def main
  kui_init("Markdown + IME Demo", 800, 600)
  kui_load_font_cjk("/Library/Fonts/Arial Unicode.ttf", 20)
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

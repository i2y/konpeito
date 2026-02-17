# Castella UI - DSL Style Composition Demo (NativeFrame / SDL3 + Skia Metal)
#
# Same as dsl_style_demo.rb but uses NativeFrame instead of JWMFrame.
# Run: ruby examples/castella_ui/native_dsl_style_demo.rb

require_relative "../../lib/konpeito/ui/castella_native"

# Global theme
$theme = Theme.new

class StyleDemoComponent < Component
  def initialize
    super
    @likes = state(0)
  end

  def view
    likes_text = @likes.value.to_s

    page_pad = Style.new.padding(20.0)
    page_space = Style.new.spacing(16.0)
    page_style = page_pad + page_space

    card_style = Style.new
    card_style.bg_color(0xFF24283B)
    card_style.border_color(0xFF414868)
    card_style.border_radius(12.0)

    card_body_pad = Style.new.padding(16.0)
    card_body_space = Style.new.spacing(8.0)
    card_body = card_body_pad + card_body_space

    header_row = Style.new.fixed_height(32.0)
    action_row = Style.new.fixed_height(40.0)

    scroll_style = Style.new.scrollable
    scroll_page = page_style + scroll_style
    column(scroll_page) {
      text("Style Composition Demo", font_size: 22.0, color: 0xFFC0CAF5)
      text("Styles combined with + operator", font_size: 13.0, color: 0xFF565F89)

      divider

      container(card_style) {
        column(card_body) {
          row(header_row) {
            text("Profile", font_size: 16.0, color: 0xFF7AA2F7)
            spacer
            text("Active", font_size: 12.0, color: 0xFF9ECE6A)
          }
          divider
          text("Taro Yamada", font_size: 14.0, color: 0xFFC0CAF5)
          text("Ruby developer", font_size: 12.0, color: 0xFF565F89)
        }
      }

      container(card_style) {
        column(card_body) {
          row(header_row) {
            text("Stats", font_size: 16.0, color: 0xFF7AA2F7)
            spacer
          }
          divider
          row {
            text("Likes:", font_size: 13.0, color: 0xFFA9B1D6)
            spacer.fixed_width(8.0)
            text(likes_text, font_size: 14.0, color: 0xFFBB9AF7)
          }
          row(action_row) {
            button(" +1 ", font_size: 14.0) { @likes += 1 }
            spacer.fixed_width(8.0)
            button(" Reset ", font_size: 14.0) { @likes.set(0) }
          }
        }
      }

      green_border = Style.new.border_color(0xFF9ECE6A)
      green_card = card_style + green_border
      container(green_card) {
        column(card_body) {
          text("About", font_size: 16.0, color: 0xFF9ECE6A)
          divider
          text("Styles are plain Style objects.", font_size: 13.0, color: 0xFFA9B1D6)
          text("Combine them with + for reuse.", font_size: 13.0, color: 0xFFA9B1D6)
          text("card_style + Style.border_color(green)", font_size: 11.0, color: 0xFF565F89)
        }
      }

      spacer
    }
  end
end

frame = NativeFrame.new("Castella Style Demo", 420, 520)
app = App.new(frame, StyleDemoComponent.new)
app.run

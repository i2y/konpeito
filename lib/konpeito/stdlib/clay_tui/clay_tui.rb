# frozen_string_literal: true

# Konpeito stdlib: ClayTUI — Clay layout + termbox2 terminal renderer (Ruby stubs)
#
# These empty method definitions allow the Ruby source to reference ClayTUI
# methods. The actual implementations are in clay_tui_native.c and are linked
# directly via @cfunc annotations in clay_tui.rbs.

module ClayTUI
  # Lifecycle
  def self.init(w, h) end
  def self.destroy() end
  def self.begin_layout() end
  def self.end_layout() end
  def self.set_dimensions(w, h) end
  def self.set_measure_text() end

  # Element Construction
  def self.open(id) end
  def self.open_i(id, index) end
  def self.close() end

  # Layout Direction
  def self.hbox() end
  def self.vbox() end

  # Padding & Gap
  def self.pad(l, r, t, b) end
  def self.gap(gap) end

  # Sizing (Width)
  def self.width_fit() end
  def self.width_grow() end
  def self.width_fixed(v) end
  def self.width_percent(v) end

  # Sizing (Height)
  def self.height_fit() end
  def self.height_grow() end
  def self.height_fixed(v) end
  def self.height_percent(v) end

  # Alignment
  def self.align(ax, ay) end

  # Decoration
  def self.bg(r, g, b) end
  def self.bg_ex(r, g, b, a, cr) end
  def self.border(r, g, b, a, top, right, bottom, left, cr) end

  # Text
  def self.text(str, r, g, b) end
  def self.text_ex(str, fid, fsz, r, g, b, a, wrap) end

  # Scroll & Floating
  def self.scroll(h, v) end
  def self.floating(ox, oy, z, att_elem, att_parent) end

  # Pointer Input
  def self.set_pointer(x, y, down) end
  def self.pointer_over(id) end
  def self.pointer_over_i(id, i) end
  def self.update_scroll(dx, dy, dt) end

  # Rendering
  def self.render() end

  # Events
  def self.peek_event(timeout_ms) end
  def self.poll_event() end
  def self.event_type() end
  def self.event_key() end
  def self.event_ch() end
  def self.event_mouse_x() end
  def self.event_mouse_y() end
  def self.event_w() end
  def self.event_h() end

  # Terminal Info
  def self.term_width() end
  def self.term_height() end

  # Key Constants
  def self.key_esc() end
  def self.key_enter() end
  def self.key_tab() end
  def self.key_backspace() end
  def self.key_arrow_up() end
  def self.key_arrow_down() end
  def self.key_arrow_left() end
  def self.key_arrow_right() end
  def self.key_space() end

  # Color Constants
  def self.color_default() end
  def self.color_black() end
  def self.color_red() end
  def self.color_green() end
  def self.color_yellow() end
  def self.color_blue() end
  def self.color_magenta() end
  def self.color_cyan() end
  def self.color_white() end

  # Attributes
  def self.attr_bold() end
  def self.attr_underline() end
  def self.attr_reverse() end

  # Color Helper
  def self.rgb(r, g, b) end
end

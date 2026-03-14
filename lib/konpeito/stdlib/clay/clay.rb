# frozen_string_literal: true

# Konpeito stdlib: Clay UI layout bindings (Ruby stubs)
#
# These empty method definitions allow the Ruby source to reference Clay
# methods. The actual implementations are in clay_native.c and are linked
# directly via @cfunc annotations in clay.rbs.

module Clay
  # Lifecycle
  def self.init(w, h) end
  def self.destroy() end
  def self.begin_layout() end
  def self.end_layout() end
  def self.set_dimensions(w, h) end

  # Input
  def self.set_pointer(x, y, down) end
  def self.pointer_over(id) end
  def self.pointer_over_i(id, index) end

  # Element Construction
  def self.open(id) end
  def self.open_i(id, index) end
  def self.close() end
  def self.layout(dir, pl, pr, pt, pb, gap, swt, swv, sht, shv, ax, ay) end
  def self.bg(r, g, b, a, corner_radius) end
  def self.border(r, g, b, a, top, right, bottom, left, corner_radius) end
  def self.scroll(horizontal, vertical) end
  def self.floating(ox, oy, z, att_elem, att_parent) end

  # Text
  def self.text(text, font_id, font_size, r, g, b, a, wrap) end
  def self.set_measure_text_raylib() end
  def self.load_font(path, size) end

  # Render Command Access
  def self.cmd_type(index) end
  def self.cmd_x(index) end
  def self.cmd_y(index) end
  def self.cmd_width(index) end
  def self.cmd_height(index) end
  def self.cmd_color_r(index) end
  def self.cmd_color_g(index) end
  def self.cmd_color_b(index) end
  def self.cmd_color_a(index) end
  def self.cmd_text(index) end
  def self.cmd_font_id(index) end
  def self.cmd_font_size(index) end
  def self.cmd_corner_radius(index) end
  def self.cmd_border_width_top(index) end

  # Bulk Rendering
  def self.render_raylib() end

  # Scroll
  def self.update_scroll(dx, dy, dt) end

  # Constants
  def self.sizing_fit() end
  def self.sizing_grow() end
  def self.sizing_fixed() end
  def self.sizing_percent() end
  def self.left_to_right() end
  def self.top_to_bottom() end

  # Text Buffer System
  def self.textbuf_clear(id) end
  def self.textbuf_putchar(id, ch) end
  def self.textbuf_backspace(id) end
  def self.textbuf_delete(id) end
  def self.textbuf_cursor_left(id) end
  def self.textbuf_cursor_right(id) end
  def self.textbuf_cursor_home(id) end
  def self.textbuf_cursor_end(id) end
  def self.textbuf_len(id) end
  def self.textbuf_cursor(id) end
  def self.textbuf_render(id, fid, fsz, r, g, b) end
  def self.textbuf_render_range(id, start_pos, end_pos, fid, fsz, r, g, b) end
  def self.text_char(ch, fid, fsz, r, g, b) end
end

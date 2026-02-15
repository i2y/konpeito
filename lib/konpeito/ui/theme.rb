# rbs_inline: enabled

# Theme system - design tokens for consistent styling
# Port of Castella Theme
#
# Kind constants for semantic widget styling
KIND_NORMAL = 0
KIND_INFO = 1
KIND_SUCCESS = 2
KIND_WARNING = 3
KIND_DANGER = 4

class Theme
  def initialize
    # Tokyo Night defaults
    @bg_canvas = 0xFF1A1B26
    @bg_primary = 0xFF24283B
    @bg_secondary = 0xFF414868
    @bg_overlay = 0xFF1A1B26
    @text_primary = 0xFFC0CAF5
    @text_secondary = 0xFF565F89
    @accent = 0xFF7AA2F7
    @info = 0xFF7AA2F7
    @error = 0xFFF7768E
    @success = 0xFF9ECE6A
    @warning = 0xFFE0AF68
    @border = 0xFF414868
    @border_focus = 0xFF7AA2F7
    @font_family = "default"
    @font_size_sm = 12.0
    @font_size_md = 14.0
    @font_size_lg = 18.0
    @font_size_xl = 24.0
    @spacing_xs = 4.0
    @spacing_sm = 8.0
    @spacing_md = 12.0
    @spacing_lg = 16.0
    @border_radius = 4.0

    # Kind-specific background colors
    @bg_info = 0xFF7AA2F7
    @bg_success = 0xFF9ECE6A
    @bg_warning = 0xFFE0AF68
    @bg_danger = 0xFFF7768E

    # Kind-specific text colors (text on colored bg)
    @text_on_info = 0xFF1A1B26
    @text_on_success = 0xFF1A1B26
    @text_on_warning = 0xFF1A1B26
    @text_on_danger = 0xFF1A1B26

    # Kind-specific hover colors
    @hover_normal = 0xFF414868
    @hover_info = 0xFF89B4FA
    @hover_success = 0xFFB9F27C
    @hover_warning = 0xFFFFD280
    @hover_danger = 0xFFFF9E9E

    # Scrollbar colors
    @scrollbar_bg = 0xFF2A2D3D
    @scrollbar_fg = 0xFF565F89

    # Selection highlight (50% alpha blue)
    @bg_selected = 0x807AA2F7
  end

  # --- Background colors ---
  #: () -> Integer
  def bg_canvas
    @bg_canvas
  end
  #: (Integer v) -> Integer
  def bg_canvas=(v)
    @bg_canvas = v
  end
  #: () -> Integer
  def bg_primary
    @bg_primary
  end
  #: (Integer v) -> Integer
  def bg_primary=(v)
    @bg_primary = v
  end
  #: () -> Integer
  def bg_secondary
    @bg_secondary
  end
  #: (Integer v) -> Integer
  def bg_secondary=(v)
    @bg_secondary = v
  end
  #: () -> Integer
  def bg_overlay
    @bg_overlay
  end
  #: (Integer v) -> Integer
  def bg_overlay=(v)
    @bg_overlay = v
  end

  # --- Text colors ---
  #: () -> Integer
  def text_primary
    @text_primary
  end
  #: (Integer v) -> Integer
  def text_primary=(v)
    @text_primary = v
  end
  #: () -> Integer
  def text_secondary
    @text_secondary
  end
  #: (Integer v) -> Integer
  def text_secondary=(v)
    @text_secondary = v
  end

  # --- Semantic colors ---
  #: () -> Integer
  def accent
    @accent
  end
  #: (Integer v) -> Integer
  def accent=(v)
    @accent = v
  end
  #: () -> Integer
  def info
    @info
  end
  #: (Integer v) -> Integer
  def info=(v)
    @info = v
  end
  #: () -> Integer
  def error
    @error
  end
  #: (Integer v) -> Integer
  def error=(v)
    @error = v
  end
  #: () -> Integer
  def success
    @success
  end
  #: (Integer v) -> Integer
  def success=(v)
    @success = v
  end
  #: () -> Integer
  def warning
    @warning
  end
  #: (Integer v) -> Integer
  def warning=(v)
    @warning = v
  end

  # --- Border ---
  #: () -> Integer
  def border
    @border
  end
  #: (Integer v) -> Integer
  def border=(v)
    @border = v
  end
  #: () -> Integer
  def border_focus
    @border_focus
  end
  #: (Integer v) -> Integer
  def border_focus=(v)
    @border_focus = v
  end

  # --- Typography ---
  #: () -> String
  def font_family
    @font_family
  end
  #: (String v) -> String
  def font_family=(v)
    @font_family = v
  end
  #: () -> Float
  def font_size_sm
    @font_size_sm
  end
  #: () -> Float
  def font_size_md
    @font_size_md
  end
  #: () -> Float
  def font_size_lg
    @font_size_lg
  end
  #: () -> Float
  def font_size_xl
    @font_size_xl
  end

  # --- Spacing ---
  #: () -> Float
  def spacing_xs
    @spacing_xs
  end
  #: () -> Float
  def spacing_sm
    @spacing_sm
  end
  #: () -> Float
  def spacing_md
    @spacing_md
  end
  #: () -> Float
  def spacing_lg
    @spacing_lg
  end
  #: () -> Float
  def border_radius
    @border_radius
  end

  # --- Scrollbar ---
  #: () -> Integer
  def scrollbar_bg
    @scrollbar_bg
  end
  #: (Integer v) -> Integer
  def scrollbar_bg=(v)
    @scrollbar_bg = v
  end
  #: () -> Integer
  def scrollbar_fg
    @scrollbar_fg
  end
  #: (Integer v) -> Integer
  def scrollbar_fg=(v)
    @scrollbar_fg = v
  end

  # --- Selection ---
  #: () -> Integer
  def bg_selected
    @bg_selected
  end
  #: (Integer v) -> Integer
  def bg_selected=(v)
    @bg_selected = v
  end

  # --- Kind backgrounds ---
  #: () -> Integer
  def bg_info
    @bg_info
  end
  #: (Integer v) -> Integer
  def bg_info=(v)
    @bg_info = v
  end
  #: () -> Integer
  def bg_success
    @bg_success
  end
  #: (Integer v) -> Integer
  def bg_success=(v)
    @bg_success = v
  end
  #: () -> Integer
  def bg_warning
    @bg_warning
  end
  #: (Integer v) -> Integer
  def bg_warning=(v)
    @bg_warning = v
  end
  #: () -> Integer
  def bg_danger
    @bg_danger
  end
  #: (Integer v) -> Integer
  def bg_danger=(v)
    @bg_danger = v
  end

  # --- Kind text on bg ---
  #: () -> Integer
  def text_on_info
    @text_on_info
  end
  #: (Integer v) -> Integer
  def text_on_info=(v)
    @text_on_info = v
  end
  #: () -> Integer
  def text_on_success
    @text_on_success
  end
  #: (Integer v) -> Integer
  def text_on_success=(v)
    @text_on_success = v
  end
  #: () -> Integer
  def text_on_warning
    @text_on_warning
  end
  #: (Integer v) -> Integer
  def text_on_warning=(v)
    @text_on_warning = v
  end
  #: () -> Integer
  def text_on_danger
    @text_on_danger
  end
  #: (Integer v) -> Integer
  def text_on_danger=(v)
    @text_on_danger = v
  end

  # --- Kind hover ---
  #: () -> Integer
  def hover_normal
    @hover_normal
  end
  #: (Integer v) -> Integer
  def hover_normal=(v)
    @hover_normal = v
  end
  #: () -> Integer
  def hover_info
    @hover_info
  end
  #: (Integer v) -> Integer
  def hover_info=(v)
    @hover_info = v
  end
  #: () -> Integer
  def hover_success
    @hover_success
  end
  #: (Integer v) -> Integer
  def hover_success=(v)
    @hover_success = v
  end
  #: () -> Integer
  def hover_warning
    @hover_warning
  end
  #: (Integer v) -> Integer
  def hover_warning=(v)
    @hover_warning = v
  end
  #: () -> Integer
  def hover_danger
    @hover_danger
  end
  #: (Integer v) -> Integer
  def hover_danger=(v)
    @hover_danger = v
  end

  # --- Kind-based color methods ---

  #: (Integer kind) -> Integer
  def button_bg(kind)
    if kind == 1
      @bg_info
    elsif kind == 2
      @bg_success
    elsif kind == 3
      @bg_warning
    elsif kind == 4
      @bg_danger
    else
      @accent
    end
  end

  #: (Integer kind) -> Integer
  def button_text(kind)
    if kind == 1
      @text_on_info
    elsif kind == 2
      @text_on_success
    elsif kind == 3
      @text_on_warning
    elsif kind == 4
      @text_on_danger
    else
      @bg_canvas
    end
  end

  #: (Integer kind) -> Integer
  def button_hover(kind)
    if kind == 1
      @hover_info
    elsif kind == 2
      @hover_success
    elsif kind == 3
      @hover_warning
    elsif kind == 4
      @hover_danger
    else
      @hover_normal
    end
  end

  #: (Integer kind) -> Integer
  def text_color_for_kind(kind)
    if kind == 1
      @info
    elsif kind == 2
      @success
    elsif kind == 3
      @warning
    elsif kind == 4
      @error
    else
      @text_primary
    end
  end
end

# --- Theme Presets ---
# Each returns a new Theme with preset colors.
# Usage: $theme = theme_nord()

#: () -> Theme
def theme_tokyo_night
  Theme.new
end

#: () -> Theme
def theme_light
  t = Theme.new
  t.bg_canvas = 0xFFD5D6DB
  t.bg_primary = 0xFFE1E2E7
  t.bg_secondary = 0xFFC4C5CB
  t.bg_overlay = 0xFFD5D6DB
  t.text_primary = 0xFF343B58
  t.text_secondary = 0xFF9699A3
  t.accent = 0xFF34548A
  t.info = 0xFF166775
  t.success = 0xFF485E30
  t.warning = 0xFF8F5E15
  t.error = 0xFF8C4351
  t.border = 0xFFC4C5CB
  t.border_focus = 0xFF34548A
  t.bg_info = 0xFF166775
  t.bg_success = 0xFF485E30
  t.bg_warning = 0xFF8F5E15
  t.bg_danger = 0xFF8C4351
  t.text_on_info = 0xFFE1E2E7
  t.text_on_success = 0xFFE1E2E7
  t.text_on_warning = 0xFFE1E2E7
  t.text_on_danger = 0xFFE1E2E7
  t.hover_info = 0xFF1A7A8A
  t.hover_success = 0xFF567236
  t.hover_warning = 0xFFA87020
  t.hover_danger = 0xFFA35060
  t.hover_normal = 0xFFC4C5CB
  t.scrollbar_bg = 0xFFC4C5CB
  t.scrollbar_fg = 0xFF9699A3
  t.bg_selected = 0x8034548A
  t
end

#: () -> Theme
def theme_nord
  t = Theme.new
  t.bg_canvas = 0xFF2E3440
  t.bg_primary = 0xFF3B4252
  t.bg_secondary = 0xFF434C5E
  t.text_primary = 0xFFECEFF4
  t.text_secondary = 0xFFD8DEE9
  t.accent = 0xFF88C0D0
  t.info = 0xFF88C0D0
  t.success = 0xFFA3BE8C
  t.warning = 0xFFEBCB8B
  t.error = 0xFFBF616A
  t.border = 0xFF4C566A
  t.border_focus = 0xFF88C0D0
  t.bg_info = 0xFF88C0D0
  t.bg_success = 0xFFA3BE8C
  t.bg_warning = 0xFFEBCB8B
  t.bg_danger = 0xFFBF616A
  t.text_on_info = 0xFF2E3440
  t.text_on_success = 0xFF2E3440
  t.text_on_warning = 0xFF2E3440
  t.text_on_danger = 0xFFECEFF4
  t.hover_info = 0xFF8FBCBB
  t.hover_success = 0xFFB4D89C
  t.hover_warning = 0xFFF5D9A0
  t.hover_danger = 0xFFD08770
  t.hover_normal = 0xFF4C566A
  t
end

#: () -> Theme
def theme_dracula
  t = Theme.new
  t.bg_canvas = 0xFF282A36
  t.bg_primary = 0xFF44475A
  t.bg_secondary = 0xFF6272A4
  t.text_primary = 0xFFF8F8F2
  t.text_secondary = 0xFF6272A4
  t.accent = 0xFFBD93F9
  t.info = 0xFF8BE9FD
  t.success = 0xFF50FA7B
  t.warning = 0xFFF1FA8C
  t.error = 0xFFFF5555
  t.border = 0xFF6272A4
  t.border_focus = 0xFFBD93F9
  t.bg_info = 0xFF8BE9FD
  t.bg_success = 0xFF50FA7B
  t.bg_warning = 0xFFF1FA8C
  t.bg_danger = 0xFFFF5555
  t.text_on_info = 0xFF282A36
  t.text_on_success = 0xFF282A36
  t.text_on_warning = 0xFF282A36
  t.text_on_danger = 0xFFF8F8F2
  t.hover_info = 0xFFA4F0FF
  t.hover_success = 0xFF69FF94
  t.hover_warning = 0xFFFFFFA5
  t.hover_danger = 0xFFFF6E6E
  t.hover_normal = 0xFF6272A4
  t
end

#: () -> Theme
def theme_catppuccin
  t = Theme.new
  t.bg_canvas = 0xFF1E1E2E
  t.bg_primary = 0xFF313244
  t.bg_secondary = 0xFF45475A
  t.text_primary = 0xFFCDD6F4
  t.text_secondary = 0xFFA6ADC8
  t.accent = 0xFFCBA6F7
  t.info = 0xFF89B4FA
  t.success = 0xFFA6E3A1
  t.warning = 0xFFF9E2AF
  t.error = 0xFFF38BA8
  t.border = 0xFF585B70
  t.border_focus = 0xFFCBA6F7
  t.bg_info = 0xFF89B4FA
  t.bg_success = 0xFFA6E3A1
  t.bg_warning = 0xFFF9E2AF
  t.bg_danger = 0xFFF38BA8
  t.text_on_info = 0xFF1E1E2E
  t.text_on_success = 0xFF1E1E2E
  t.text_on_warning = 0xFF1E1E2E
  t.text_on_danger = 0xFF1E1E2E
  t.hover_info = 0xFFA4C8FF
  t.hover_success = 0xFFB9F0B4
  t.hover_warning = 0xFFFFF0CC
  t.hover_danger = 0xFFFFA0B8
  t.hover_normal = 0xFF585B70
  t
end

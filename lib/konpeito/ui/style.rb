# rbs_inline: enabled

# Style - composable widget style (CSS-inspired)
#
# Collects layout, visual, and typography properties and applies them to widgets.
# Each setter returns self for chaining.
# Compose via .then(other) or + to merge two Styles.
#
# Usage (with DSL s() helper):
#   s.spacing(8).scrollable
#   s.font_size(24).color(0xFFC0CAF5).bold
#   style_a + style_b
#
# Note: Float fields use boolean flags instead of nil to avoid
# JVM null-unboxing issues (nil in Float field causes NPE).

class Style
  def initialize
    # Layout (Widget common)
    @has_fixed_width = false
    @fixed_width_val = 0
    @has_fixed_height = false
    @fixed_height_val = 0
    @fit_content_val = false
    @has_flex = false
    @flex_val = 1
    @has_padding = false
    @pad_top = 0
    @pad_right = 0
    @pad_bottom = 0
    @pad_left = 0
    # Container (Column/Row)
    @has_spacing = false
    @spacing_val = 0
    @scrollable_val = false
    @pin_bottom_val = false
    @pin_end_val = false
    # Container wrapper (Container widget)
    @has_bg_color = false
    @bg_color_val = 0
    @has_border_color = false
    @border_color_val = 0
    @has_border_radius = false
    @border_radius_val = 0
    # Text properties
    @has_font_size = false
    @font_size_val = 0
    # Expanding policy
    @has_expanding = false
    @expanding_width_val = false
    @expanding_height_val = false
    # Typography (text visual)
    @has_color = false
    @color_val = 0
    @has_text_color = false
    @text_color_val = 0
    @bold_val = false
    @italic_val = false
    @has_align = false
    @align_val = 0
    @has_font_family = false
    @font_family_val = "default"
    @has_kind = false
    @kind_val = 0
  end

  # --- Class methods: create new Style with one property set ---

  #: (Float w) -> Style
  def self.fixed_width(w)
    Style.new.fixed_width(w)
  end

  #: (Float w) -> Style
  def self.width(w)
    Style.new.fixed_width(w)
  end

  #: (Float h) -> Style
  def self.fixed_height(h)
    Style.new.fixed_height(h)
  end

  #: (Float h) -> Style
  def self.height(h)
    Style.new.fixed_height(h)
  end

  #: (Float w, Float h) -> Style
  def self.size(w, h)
    Style.new.size(w, h)
  end

  #: () -> Style
  def self.fit_content
    Style.new.fit_content
  end

  #: (Integer f) -> Style
  def self.flex(f)
    Style.new.flex(f)
  end

  #: (Float v) -> Style
  def self.padding(v)
    Style.new.padding(v)
  end

  #: (Float v) -> Style
  def self.spacing(v)
    Style.new.spacing(v)
  end

  #: () -> Style
  def self.scrollable
    Style.new.scrollable
  end

  #: () -> Style
  def self.pin_to_bottom
    Style.new.pin_to_bottom
  end

  #: () -> Style
  def self.pin_to_end
    Style.new.pin_to_end
  end

  #: (Integer c) -> Style
  def self.bg_color(c)
    Style.new.bg_color(c)
  end

  #: (Integer c) -> Style
  def self.border_color(c)
    Style.new.border_color(c)
  end

  #: (Float r) -> Style
  def self.border_radius(r)
    Style.new.border_radius(r)
  end

  #: (Float s) -> Style
  def self.font_size(s)
    Style.new.font_size(s)
  end

  #: () -> Style
  def self.expanding
    Style.new.expanding
  end

  #: () -> Style
  def self.expanding_width
    Style.new.expanding_width
  end

  #: () -> Style
  def self.expanding_height
    Style.new.expanding_height
  end

  #: (Integer c) -> Style
  def self.color(c)
    Style.new.color(c)
  end

  #: (Integer c) -> Style
  def self.text_color(c)
    Style.new.text_color(c)
  end

  #: () -> Style
  def self.bold
    Style.new.bold
  end

  #: () -> Style
  def self.italic
    Style.new.italic
  end

  #: (Integer a) -> Style
  def self.align(a)
    Style.new.align(a)
  end

  #: (String f) -> Style
  def self.font_family(f)
    Style.new.font_family(f)
  end

  #: (Integer k) -> Style
  def self.kind(k)
    Style.new.kind(k)
  end

  # --- Instance methods: chainable setters ---

  #: (Float w) -> Style
  def fixed_width(w)
    @has_fixed_width = true
    @fixed_width_val = w
    self
  end

  #: (Float w) -> Style
  def width(w)
    @has_fixed_width = true
    @fixed_width_val = w
    self
  end

  #: (Float h) -> Style
  def fixed_height(h)
    @has_fixed_height = true
    @fixed_height_val = h
    self
  end

  #: (Float h) -> Style
  def height(h)
    @has_fixed_height = true
    @fixed_height_val = h
    self
  end

  #: (Float w, Float h) -> Style
  def size(w, h)
    @has_fixed_width = true
    @fixed_width_val = w
    @has_fixed_height = true
    @fixed_height_val = h
    self
  end

  #: () -> Style
  def fit_content
    @fit_content_val = true
    self
  end

  #: (Integer f) -> Style
  def flex(f)
    @has_flex = true
    @flex_val = f
    self
  end

  #: (Float v) -> Style
  def padding(v)
    @has_padding = true
    @pad_top = v
    @pad_right = v
    @pad_bottom = v
    @pad_left = v
    self
  end

  #: (Float v) -> Style
  def spacing(v)
    @has_spacing = true
    @spacing_val = v
    self
  end

  #: () -> Style
  def scrollable
    @scrollable_val = true
    self
  end

  #: () -> Style
  def pin_to_bottom
    @pin_bottom_val = true
    self
  end

  #: () -> Style
  def pin_to_end
    @pin_end_val = true
    self
  end

  #: (Integer c) -> Style
  def bg_color(c)
    @has_bg_color = true
    @bg_color_val = c
    self
  end

  #: (Integer c) -> Style
  def border_color(c)
    @has_border_color = true
    @border_color_val = c
    self
  end

  #: (Float r) -> Style
  def border_radius(r)
    @has_border_radius = true
    @border_radius_val = r
    self
  end

  #: (Float s) -> Style
  def font_size(s)
    @has_font_size = true
    @font_size_val = s
    self
  end

  #: () -> Style
  def expanding
    @has_expanding = true
    @expanding_width_val = true
    @expanding_height_val = true
    self
  end

  #: () -> Style
  def expanding_width
    @has_expanding = true
    @expanding_width_val = true
    self
  end

  #: () -> Style
  def expanding_height
    @has_expanding = true
    @expanding_height_val = true
    self
  end

  # --- Typography setters ---

  #: (Integer c) -> Style
  def color(c)
    @has_color = true
    @color_val = c
    self
  end

  #: (Integer c) -> Style
  def text_color(c)
    @has_text_color = true
    @text_color_val = c
    self
  end

  #: () -> Style
  def bold
    @bold_val = true
    self
  end

  #: () -> Style
  def italic
    @italic_val = true
    self
  end

  #: (Integer a) -> Style
  def align(a)
    @has_align = true
    @align_val = a
    self
  end

  #: (String f) -> Style
  def font_family(f)
    @has_font_family = true
    @font_family_val = f
    self
  end

  #: (Integer k) -> Style
  def kind(k)
    @has_kind = true
    @kind_val = k
    self
  end

  # --- Composition ---

  #: (Style other) -> Style
  def then(other)
    result = Style.new
    result.merge_from(self)
    result.merge_from(other)
    result
  end

  #: (Style other) -> Style
  def +(other)
    result = Style.new
    result.merge_from(self)
    result.merge_from(other)
    result
  end

  #: (Style src) -> void
  def merge_from(src)
    if src.get_has_fixed_width
      @has_fixed_width = true
      @fixed_width_val = src.get_fixed_width
    end
    if src.get_has_fixed_height
      @has_fixed_height = true
      @fixed_height_val = src.get_fixed_height
    end
    if src.get_fit_content
      @fit_content_val = true
    end
    if src.get_has_flex
      @has_flex = true
      @flex_val = src.get_flex
    end
    if src.get_has_padding
      @has_padding = true
      @pad_top = src.get_pad_top
      @pad_right = src.get_pad_right
      @pad_bottom = src.get_pad_bottom
      @pad_left = src.get_pad_left
    end
    if src.get_has_spacing
      @has_spacing = true
      @spacing_val = src.get_spacing
    end
    if src.get_scrollable
      @scrollable_val = true
    end
    if src.get_pin_bottom
      @pin_bottom_val = true
    end
    if src.get_pin_end
      @pin_end_val = true
    end
    if src.get_has_bg_color
      @has_bg_color = true
      @bg_color_val = src.get_bg_color
    end
    if src.get_has_border_color
      @has_border_color = true
      @border_color_val = src.get_border_color
    end
    if src.get_has_border_radius
      @has_border_radius = true
      @border_radius_val = src.get_border_radius
    end
    if src.get_has_font_size
      @has_font_size = true
      @font_size_val = src.get_font_size
    end
    if src.get_has_expanding
      @has_expanding = true
      @expanding_width_val = src.get_expanding_width
      @expanding_height_val = src.get_expanding_height
    end
    # Typography
    if src.get_has_color
      @has_color = true
      @color_val = src.get_color
    end
    if src.get_has_text_color
      @has_text_color = true
      @text_color_val = src.get_text_color
    end
    if src.get_bold
      @bold_val = true
    end
    if src.get_italic
      @italic_val = true
    end
    if src.get_has_align
      @has_align = true
      @align_val = src.get_align
    end
    if src.get_has_font_family
      @has_font_family = true
      @font_family_val = src.get_font_family
    end
    if src.get_has_kind
      @has_kind = true
      @kind_val = src.get_kind
    end
  end

  # --- Getters (for merge_from) ---

  #: () -> bool
  def get_has_fixed_width
    @has_fixed_width
  end

  #: () -> Float
  def get_fixed_width
    @fixed_width_val
  end

  #: () -> bool
  def get_has_fixed_height
    @has_fixed_height
  end

  #: () -> Float
  def get_fixed_height
    @fixed_height_val
  end

  #: () -> bool
  def get_fit_content
    @fit_content_val
  end

  #: () -> bool
  def get_has_flex
    @has_flex
  end

  #: () -> Integer
  def get_flex
    @flex_val
  end

  #: () -> bool
  def get_has_padding
    @has_padding
  end

  #: () -> Float
  def get_pad_top
    @pad_top
  end

  #: () -> Float
  def get_pad_right
    @pad_right
  end

  #: () -> Float
  def get_pad_bottom
    @pad_bottom
  end

  #: () -> Float
  def get_pad_left
    @pad_left
  end

  #: () -> bool
  def get_has_spacing
    @has_spacing
  end

  #: () -> Float
  def get_spacing
    @spacing_val
  end

  #: () -> bool
  def get_scrollable
    @scrollable_val
  end

  #: () -> bool
  def get_pin_bottom
    @pin_bottom_val
  end

  #: () -> bool
  def get_pin_end
    @pin_end_val
  end

  #: () -> bool
  def get_has_bg_color
    @has_bg_color
  end

  #: () -> Integer
  def get_bg_color
    @bg_color_val
  end

  #: () -> bool
  def get_has_border_color
    @has_border_color
  end

  #: () -> Integer
  def get_border_color
    @border_color_val
  end

  #: () -> bool
  def get_has_border_radius
    @has_border_radius
  end

  #: () -> Float
  def get_border_radius
    @border_radius_val
  end

  #: () -> bool
  def get_has_font_size
    @has_font_size
  end

  #: () -> Float
  def get_font_size
    @font_size_val
  end

  #: () -> bool
  def get_has_expanding
    @has_expanding
  end

  #: () -> bool
  def get_expanding_width
    @expanding_width_val
  end

  #: () -> bool
  def get_expanding_height
    @expanding_height_val
  end

  # Typography getters

  #: () -> bool
  def get_has_color
    @has_color
  end

  #: () -> Integer
  def get_color
    @color_val
  end

  #: () -> bool
  def get_has_text_color
    @has_text_color
  end

  #: () -> Integer
  def get_text_color
    @text_color_val
  end

  #: () -> bool
  def get_bold
    @bold_val
  end

  #: () -> bool
  def get_italic
    @italic_val
  end

  #: () -> bool
  def get_has_align
    @has_align
  end

  #: () -> Integer
  def get_align
    @align_val
  end

  #: () -> bool
  def get_has_font_family
    @has_font_family
  end

  #: () -> String
  def get_font_family
    @font_family_val
  end

  #: () -> bool
  def get_has_kind
    @has_kind
  end

  #: () -> Integer
  def get_kind
    @kind_val
  end

  # --- Apply to widget (explicit dispatch, no send/method_missing) ---

  #: (untyped widget) -> untyped
  def apply_layout(widget)
    if @has_fixed_width
      widget.fixed_width(@fixed_width_val)
    end
    if @has_fixed_height
      widget.fixed_height(@fixed_height_val)
    end
    if @fit_content_val
      widget.fit_content
    end
    if @has_flex
      widget.flex(@flex_val)
    end
    if @has_padding
      widget.padding(@pad_top, @pad_right, @pad_bottom, @pad_left)
    end
    if @has_expanding
      if @expanding_width_val
        widget.set_width_policy(EXPANDING)
      end
      if @expanding_height_val
        widget.set_height_policy(EXPANDING)
      end
    end
    widget
  end

  #: (untyped widget) -> untyped
  def apply_container(widget)
    if @has_spacing
      widget.spacing(@spacing_val)
    end
    if @scrollable_val
      widget.scrollable
    end
    if @pin_bottom_val
      widget.pin_to_bottom
    end
    if @pin_end_val
      widget.pin_to_end
    end
    widget
  end

  #: (untyped widget) -> untyped
  def apply_visual(widget)
    if @has_bg_color
      widget.bg_color(@bg_color_val)
    end
    if @has_border_color
      widget.border_color(@border_color_val)
    end
    if @has_border_radius
      widget.border_radius(@border_radius_val)
    end
    widget
  end

  #: (untyped widget) -> untyped
  def apply_text(widget)
    if @has_font_size
      widget.font_size(@font_size_val)
    end
    widget
  end

  #: (untyped widget) -> untyped
  def apply_typography(widget)
    if @has_font_size
      widget.font_size(@font_size_val)
    end
    if @has_color
      widget.color(@color_val)
    end
    if @has_text_color
      widget.text_color(@text_color_val)
    end
    if @bold_val
      widget.bold
    end
    if @italic_val
      widget.italic
    end
    if @has_align
      widget.align(@align_val)
    end
    if @has_font_family
      widget.font_family(@font_family_val)
    end
    if @has_kind
      widget.kind(@kind_val)
    end
    widget
  end

  #: (untyped widget) -> untyped
  def apply(widget)
    apply_layout(widget)
    apply_container(widget)
    apply_visual(widget)
    widget
  end
end

# KUI Theme Demo — shows all 7 themes
#
# Build:
#   bundle exec ruby -Ilib bin/konpeito build --target mruby \
#     -I lib/konpeito/stdlib/kui \
#     -o examples/kui_calc/theme_demo \
#     examples/kui_calc/theme_demo.rb
#
# rbs_inline: enabled

require_relative "../../lib/konpeito/stdlib/kui/kui_gui"

# @rbs module TD
# @rbs   @s: NativeArray[Integer, 4]
# @rbs end
# TD.s[0] = current theme (0-6)

#: () -> String
def theme_name
  t = TD.s[0]
  if t == 0
    return "Dark"
  end
  if t == 1
    return "Light"
  end
  if t == 2
    return "Tokyo Night"
  end
  if t == 3
    return "Nord"
  end
  if t == 4
    return "Dracula"
  end
  if t == 5
    return "Catppuccin"
  end
  return "Material"
end

#: () -> Integer
def apply_theme
  t = TD.s[0]
  if t == 0
    kui_theme_dark
  end
  if t == 1
    kui_theme_light
  end
  if t == 2
    kui_theme_tokyo_night
  end
  if t == 3
    kui_theme_nord
  end
  if t == 4
    kui_theme_dracula
  end
  if t == 5
    kui_theme_catppuccin
  end
  if t == 6
    kui_theme_material
  end
  return 0
end

#: () -> Integer
def draw
  vpanel pad: 16, gap: 12 do
    label "KUI Theme Demo", size: 24
    hpanel gap: 4 do
      label "Current:", size: 16
      label theme_name, size: 16, r: KUITheme.c[6], g: KUITheme.c[7], b: KUITheme.c[8]
    end
    divider

    # Theme buttons
    hpanel gap: 6 do
      button "Dark", size: 14 do
        TD.s[0] = 0
      end
      button "Light", size: 14 do
        TD.s[0] = 1
      end
      button "Tokyo", size: 14 do
        TD.s[0] = 2
      end
      button "Nord", size: 14 do
        TD.s[0] = 3
      end
    end
    hpanel gap: 6 do
      button "Dracula", size: 14 do
        TD.s[0] = 4
      end
      button "Catppuccin", size: 14 do
        TD.s[0] = 5
      end
      button "Material", size: 14 do
        TD.s[0] = 6
      end
    end

    divider

    # Kind buttons
    label "Kind Variants:", size: 16
    hpanel gap: 6 do
      button "Default", size: 14 do end
      button "Info", size: 14, kind: KUI_KIND_INFO do end
      button "Success", size: 14, kind: KUI_KIND_SUCCESS do end
      button "Warning", size: 14, kind: KUI_KIND_WARNING do end
      button "Danger", size: 14, kind: KUI_KIND_DANGER do end
    end

    divider

    # Sample widgets
    card pad: 12, gap: 6 do
      label "Card with content", size: 16
      progress_bar 70, 100, 200, 10
      hpanel gap: 8 do
        badge "Badge"
        badge "Info", r: KUITheme.c[32], g: KUITheme.c[33], b: KUITheme.c[34]
        badge "OK", r: KUITheme.c[24], g: KUITheme.c[25], b: KUITheme.c[26]
      end
    end

    spacer
    label "7 themes available", size: 12, r: KUITheme.c[21], g: KUITheme.c[22], b: KUITheme.c[23]
  end
  return 0
end

#: () -> Integer
def main
  TD.s[0] = 0
  kui_init("KUI Theme Demo", 500, 420)
  kui_load_font("/System/Library/Fonts/SFNS.ttf", 24)
  kui_theme_dark
  while kui_running == 1
    apply_theme
    kui_begin_frame
    draw
    kui_end_frame
  end
  kui_destroy
  return 0
end

main

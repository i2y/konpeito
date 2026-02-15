# Castella UI - umbrella require
#
# Loads all Castella UI components in one line:
#   require_relative "../../lib/konpeito/ui/castella"

# Core
require_relative "render_node"
require_relative "core"
require_relative "column"
require_relative "row"
require_relative "box"
require_relative "spacer"
require_relative "theme"

# Widgets
require_relative "widgets/text"
require_relative "widgets/button"
require_relative "widgets/divider"
require_relative "widgets/container"
require_relative "widgets/input"
require_relative "widgets/multiline_input"
require_relative "widgets/checkbox"
require_relative "widgets/radio_buttons"
require_relative "widgets/switch"
require_relative "widgets/slider"
require_relative "widgets/progress_bar"
require_relative "widgets/tabs"
require_relative "widgets/data_table"
require_relative "widgets/tree"
require_relative "widgets/calendar"
require_relative "widgets/modal"
require_relative "widgets/image"
require_relative "widgets/net_image"

# Markdown
require_relative "markdown/ast"
require_relative "markdown/theme"
require_relative "markdown/parser"
require_relative "markdown/mermaid/models"
require_relative "markdown/mermaid/parser"
require_relative "markdown/mermaid/layout"
require_relative "markdown/mermaid/renderer"
require_relative "markdown/renderer"
require_relative "widgets/markdown"

# Charts
require_relative "chart/chart_helpers"
require_relative "chart/scales"
require_relative "chart/base_chart"
require_relative "chart/bar_chart"
require_relative "chart/line_chart"
require_relative "chart/pie_chart"
require_relative "chart/scatter_chart"
require_relative "chart/area_chart"
require_relative "chart/stacked_bar_chart"
require_relative "chart/gauge_chart"
require_relative "chart/heatmap_chart"

# Animation
require_relative "animation/easing"
require_relative "animation/value_tween"
require_relative "animation/animated_state"

# Framework
require_relative "frame"
require_relative "app"

# DSL
require_relative "style"
require_relative "dsl"

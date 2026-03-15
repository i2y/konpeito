# frozen_string_literal: true

# KUI Widget State — GC-free state for complex widgets via NativeArray
#
# Used by overlay, form, and navigation widgets to track internal state
# such as drag positions, open/close flags, timers, and toast queues.
#
# Slot allocation:
#   [0-3]   drag    — active_id, start_x, start_y, current_x
#   [4-7]   timer   — tooltip_hover_id, tooltip_frames, toast_count, animation_frame
#   [8-11]  overlay — dropdown_open_id, drawer_open, drawer_progress, bottom_sheet
#   [12-15] nav     — nav_depth, nav_current, nav_back, nav_anim
#   [16-31] toast   — 4 slots x 4 (buf_id, start_frame, duration, type)
#   [32-63] reserved
#
# rbs_inline: enabled

# @rbs module KUIWidgetState
# @rbs   @s: NativeArray[Integer, 64]
# @rbs end

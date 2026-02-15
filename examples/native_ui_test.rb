#!/usr/bin/env ruby
# Simple test: open a window, draw a colored rectangle and text, wait for quit

require_relative "../lib/konpeito/stdlib/ui/konpeito_ui"

puts "Creating window..."
handle = KonpeitoUI.create_window("Konpeito UI Test", 640, 480)
puts "Window handle: #{handle}"

if handle == 0
  puts "Failed to create window!"
  exit 1
end

running = true
frame = 0

while running
  # Poll events
  KonpeitoUI.step(handle)

  while KonpeitoUI.has_event(handle)
    etype = KonpeitoUI.event_type(handle)
    case etype
    when 10  # KUI_EVENT_QUIT
      running = false
    when 1   # KUI_EVENT_MOUSE_DOWN
      x = KonpeitoUI.event_x(handle)
      y = KonpeitoUI.event_y(handle)
      puts "Mouse down at (#{x}, #{y})"
    end
    KonpeitoUI.consume_event(handle)
  end

  # Draw
  KonpeitoUI.begin_frame(handle)

  # Clear with white background
  KonpeitoUI.clear(handle, 0xFFFFFFFF)

  # Blue rectangle
  KonpeitoUI.fill_rect(handle, 50.0, 50.0, 200.0, 100.0, 0xFF4488FF)

  # Red rounded rectangle
  KonpeitoUI.fill_round_rect(handle, 300.0, 50.0, 200.0, 100.0, 12.0, 0xFFFF4444)

  # Green circle
  KonpeitoUI.fill_circle(handle, 150.0, 280.0, 60.0, 0xFF44CC44)

  # Draw text
  KonpeitoUI.draw_text(handle, "Hello from Konpeito UI!", 50.0, 400.0,
                        "Helvetica", 24.0, 0xFF000000)
  KonpeitoUI.draw_text(handle, "SDL3 + Skia (Metal GPU)", 50.0, 440.0,
                        "Helvetica", 16.0, 0xFF666666)

  KonpeitoUI.end_frame(handle)

  # Sleep a bit to avoid busy loop
  sleep(1.0 / 60.0)
end

KonpeitoUI.destroy_window(handle)
puts "Done!"

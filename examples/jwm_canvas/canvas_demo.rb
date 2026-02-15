# JWM + Skija interactive drawing demo
# NO RBS FILE NEEDED — all types auto-introspected from classpath
#
# Setup:  cd examples/jwm_canvas && bash setup.sh
# Run:    bash run.sh

canvas = Java::Konpeito::Canvas::Canvas.new("Interactive Demo", 800, 600)
canvas.set_background(0xFFF5F5F5)

# Title text
canvas.draw_text("Click to draw circles!", 220.0, 50.0, 28.0, 0xFF333333)

# Three colored circles
canvas.draw_circle(200.0, 300.0, 80.0, 0xFF4285F4)
canvas.draw_circle(400.0, 300.0, 80.0, 0xFFEA4335)
canvas.draw_circle(600.0, 300.0, 80.0, 0xFF34A853)

# Bottom banner
canvas.draw_round_rect(100.0, 470.0, 600.0, 50.0, 8.0, 0xFFFBBC05)
canvas.draw_text("Powered by JWM + Skija", 290.0, 502.0, 18.0, 0xFF333333)

# Interactive: click to draw blue circles (SAM callback auto-detected)
canvas.set_click_callback { |x, y|
  canvas.draw_circle(x, y, 25.0, 0xFF4285F4)
}

canvas.show

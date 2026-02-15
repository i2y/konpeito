# Castella UI - Hello World demo
# NO RBS FILE NEEDED - all types auto-introspected from classpath
#
# Setup:  cd examples/castella_ui && bash setup.sh
# Run:    bash run.sh hello.rb

runtime = Java::Konpeito::Ui::KUIRuntime.new("Hello Castella", 400, 300)

runtime.set_on_frame {
  runtime.clear(0xFF1A1B26)

  # Rounded button background
  runtime.fill_round_rect(50.0, 50.0, 300.0, 60.0, 8.0, 0xFF7AA2F7)
  runtime.draw_text("Hello, Castella!", 100.0, 90.0, "default", 24.0, 0xFFFFFFFF)

  # Decorative circles
  runtime.fill_circle(100.0, 200.0, 40.0, 0xFF9ECE6A)
  runtime.fill_circle(200.0, 200.0, 40.0, 0xFFE0AF68)
  runtime.fill_circle(300.0, 200.0, 40.0, 0xFFF7768E)

  # Bottom text
  runtime.draw_text("Powered by JWM + Skija", 110.0, 270.0, "default", 14.0, 0xFF565F89)
}

runtime.run

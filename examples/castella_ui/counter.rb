# Castella UI - Counter demo (minimal)
#
# Setup:  cd examples/castella_ui && bash setup.sh
# Run:    bash run.sh counter.rb

runtime = Java::Konpeito::Ui::KUIRuntime.new("Counter", 400, 300)

count = 0

runtime.set_on_frame {
  runtime.clear(0xFF1A1B26)
  runtime.draw_text("Count: #{count}", 140.0, 120.0, "default", 32.0, 0xFFC0CAF5)
  runtime.fill_round_rect(120.0, 170.0, 70.0, 40.0, 4.0, 0xFF7AA2F7)
  runtime.draw_text("-", 148.0, 197.0, "default", 20.0, 0xFF1A1B26)
  runtime.fill_round_rect(210.0, 170.0, 70.0, 40.0, 4.0, 0xFF7AA2F7)
  runtime.draw_text("+", 236.0, 197.0, "default", 20.0, 0xFF1A1B26)
}

runtime.set_on_mouse { |type, x, y, button|
  if type == 1 && x >= 120.0 && x <= 190.0 && y >= 170.0 && y <= 210.0
    count = count - 1
  end
  if type == 1 && x >= 210.0 && x <= 280.0 && y >= 170.0 && y <= 210.0
    count = count + 1
  end
}

runtime.run

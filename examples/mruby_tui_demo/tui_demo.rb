def main
  w = ClayTUI.term_width
  h = ClayTUI.term_height
  ClayTUI.init(w * 1.0, h * 1.0)
  ClayTUI.set_measure_text

  running = 1
  selected = 0
  page = 0
  cmd_output = ""
  cmd_input = "uname -a"

  while running == 1
    ClayTUI.set_dimensions(ClayTUI.term_width * 1.0, ClayTUI.term_height * 1.0)

    ClayTUI.begin_layout

      ClayTUI.open("root")
      ClayTUI.vbox
      ClayTUI.width_grow
      ClayTUI.height_grow

        # Header
        ClayTUI.open("header")
        ClayTUI.hbox
        ClayTUI.pad(1, 1, 0, 0)
        ClayTUI.width_grow
        ClayTUI.height_fit
        ClayTUI.bg(30, 80, 160)
          ClayTUI.text(" ClayTUI Demo ", 255, 255, 255)
        ClayTUI.close

        # Body (sidebar + main)
        ClayTUI.open("body")
        ClayTUI.hbox
        ClayTUI.width_grow
        ClayTUI.height_grow

          # Sidebar
          ClayTUI.open("sidebar")
          ClayTUI.vbox
          ClayTUI.pad(1, 1, 1, 1)
          ClayTUI.width_fixed(22.0)
          ClayTUI.height_grow
          ClayTUI.bg(35, 35, 35)
          ClayTUI.border(70.0, 70.0, 70.0, 255.0, 1, 1, 1, 1, 0.0)
            ClayTUI.text("Navigation", 255, 255, 0)
            ClayTUI.text("", 255, 255, 255)

            # Menu item: Home (0)
            ClayTUI.open_i("menu", 0)
            ClayTUI.hbox
            ClayTUI.width_grow
            ClayTUI.height_fit
            if selected == 0
              ClayTUI.bg(50, 100, 180)
            end
              if selected == 0
                ClayTUI.text(" > Home", 255, 255, 255)
              else
                ClayTUI.text("   Home", 160, 160, 160)
              end
            ClayTUI.close

            # Menu item: System Info (1)
            ClayTUI.open_i("menu", 1)
            ClayTUI.hbox
            ClayTUI.width_grow
            ClayTUI.height_fit
            if selected == 1
              ClayTUI.bg(50, 100, 180)
            end
              if selected == 1
                ClayTUI.text(" > System Info", 255, 255, 255)
              else
                ClayTUI.text("   System Info", 160, 160, 160)
              end
            ClayTUI.close

            # Menu item: Files (2)
            ClayTUI.open_i("menu", 2)
            ClayTUI.hbox
            ClayTUI.width_grow
            ClayTUI.height_fit
            if selected == 2
              ClayTUI.bg(50, 100, 180)
            end
              if selected == 2
                ClayTUI.text(" > Files", 255, 255, 255)
              else
                ClayTUI.text("   Files", 160, 160, 160)
              end
            ClayTUI.close

            # Menu item: Shell (3)
            ClayTUI.open_i("menu", 3)
            ClayTUI.hbox
            ClayTUI.width_grow
            ClayTUI.height_fit
            if selected == 3
              ClayTUI.bg(50, 100, 180)
            end
              if selected == 3
                ClayTUI.text(" > Shell", 255, 255, 255)
              else
                ClayTUI.text("   Shell", 160, 160, 160)
              end
            ClayTUI.close

            ClayTUI.text("", 255, 255, 255)
            ClayTUI.text(" [Q] Quit", 90, 90, 90)
          ClayTUI.close

          # Main content
          ClayTUI.open("main")
          ClayTUI.vbox
          ClayTUI.pad(2, 2, 1, 1)
          ClayTUI.width_grow
          ClayTUI.height_grow

            if page == 0
              ClayTUI.text("Welcome to ClayTUI!", 0, 255, 0)
              ClayTUI.text("", 255, 255, 255)
              ClayTUI.text("Terminal UI powered by Clay layout + termbox2.", 255, 255, 255)
              ClayTUI.text("With KonpeitoShell for shell execution.", 200, 200, 200)
              ClayTUI.text("", 255, 255, 255)
              ClayTUI.text("Use Up/Down to navigate, Enter to select.", 150, 150, 150)
              ClayTUI.text("Press Q or ESC to quit.", 150, 150, 150)
            end

            if page == 1
              ClayTUI.text("System Information", 0, 200, 255)
              ClayTUI.text("", 255, 255, 255)

              uname = KonpeitoShell.exec("uname -srm")
              ClayTUI.text("OS:   ", 255, 255, 0)
              ClayTUI.text(uname, 200, 200, 200)

              hostname = KonpeitoShell.exec("hostname")
              ClayTUI.text("Host: ", 255, 255, 0)
              ClayTUI.text(hostname, 200, 200, 200)

              user = KonpeitoShell.getenv("USER")
              ClayTUI.text("User: ", 255, 255, 0)
              ClayTUI.text(user, 200, 200, 200)

              home = KonpeitoShell.getenv("HOME")
              ClayTUI.text("Home: ", 255, 255, 0)
              ClayTUI.text(home, 200, 200, 200)

              shell = KonpeitoShell.getenv("SHELL")
              ClayTUI.text("Shell:", 255, 255, 0)
              ClayTUI.text(shell, 200, 200, 200)

              uptime = KonpeitoShell.exec("uptime | sed 's/^[ ]*//'")
              ClayTUI.text("", 255, 255, 255)
              ClayTUI.text("Uptime:", 255, 255, 0)
              ClayTUI.text(uptime, 200, 200, 200)
            end

            if page == 2
              ClayTUI.text("Files (Home Directory)", 0, 200, 255)
              ClayTUI.text("", 255, 255, 255)

              files = KonpeitoShell.exec("ls -1 ~ | head -15")
              ClayTUI.text(files, 200, 200, 200)
            end

            if page == 3
              ClayTUI.text("Shell", 0, 200, 255)
              ClayTUI.text("", 255, 255, 255)

              ClayTUI.text("Command:", 255, 255, 0)

              ClayTUI.open("cmd_display")
              ClayTUI.hbox
              ClayTUI.width_grow
              ClayTUI.height_fit
              ClayTUI.bg(50, 50, 50)
                ClayTUI.text("$ ", 100, 255, 100)
                ClayTUI.text(cmd_input, 255, 255, 255)
              ClayTUI.close

              ClayTUI.text("", 255, 255, 255)
              ClayTUI.text("[Enter] Run  [1-5] Presets", 150, 150, 150)
              ClayTUI.text("  1: uname -a", 120, 120, 120)
              ClayTUI.text("  2: date", 120, 120, 120)
              ClayTUI.text("  3: df -h | head -5", 120, 120, 120)
              ClayTUI.text("  4: ps aux | head -10", 120, 120, 120)
              ClayTUI.text("  5: git log --oneline -5", 120, 120, 120)

              if cmd_output != ""
                ClayTUI.text("", 255, 255, 255)
                ClayTUI.text("Output:", 255, 255, 0)

                ClayTUI.open("output_box")
                ClayTUI.vbox
                ClayTUI.pad(1, 1, 0, 0)
                ClayTUI.width_grow
                ClayTUI.height_fit
                ClayTUI.bg(25, 25, 25)
                  ClayTUI.text(cmd_output, 180, 220, 180)
                ClayTUI.close
              end
            end

          ClayTUI.close

        ClayTUI.close

        # Footer
        ClayTUI.open("footer")
        ClayTUI.hbox
        ClayTUI.pad(1, 1, 0, 0)
        ClayTUI.width_grow
        ClayTUI.height_fit
        ClayTUI.bg(30, 30, 30)
          ClayTUI.text(" ClayTUI + KonpeitoShell | Konpeito ", 100, 100, 100)
        ClayTUI.close

      ClayTUI.close

    ClayTUI.end_layout
    ClayTUI.render

    evt = ClayTUI.peek_event(50)
    if evt > 0
      if ClayTUI.event_type == 1
        # ESC
        if ClayTUI.event_key == ClayTUI.key_esc
          running = 0
        end

        # Arrow keys
        if ClayTUI.event_key == ClayTUI.key_arrow_up
          if selected > 0
            selected = selected - 1
          end
        end
        if ClayTUI.event_key == ClayTUI.key_arrow_down
          if selected < 3
            selected = selected + 1
          end
        end

        # Enter
        if ClayTUI.event_key == ClayTUI.key_enter
          page = selected
          if page == 3
            cmd_output = KonpeitoShell.exec(cmd_input)
          end
        end

        # Character keys
        ch = ClayTUI.event_ch
        # q/Q = quit
        if ch == 113
          running = 0
        end
        if ch == 81
          running = 0
        end

        # Shell preset commands (only on Shell page)
        if page == 3
          if ch == 49
            cmd_input = "uname -a"
            cmd_output = KonpeitoShell.exec(cmd_input)
          end
          if ch == 50
            cmd_input = "date"
            cmd_output = KonpeitoShell.exec(cmd_input)
          end
          if ch == 51
            cmd_input = "df -h | head -5"
            cmd_output = KonpeitoShell.exec(cmd_input)
          end
          if ch == 52
            cmd_input = "ps aux | head -10"
            cmd_output = KonpeitoShell.exec(cmd_input)
          end
          if ch == 53
            cmd_input = "git log --oneline -5"
            cmd_output = KonpeitoShell.exec(cmd_input)
          end
        end
      end

      if ClayTUI.event_type == 2
        ClayTUI.set_dimensions(ClayTUI.event_w * 1.0, ClayTUI.event_h * 1.0)
      end
    end
  end

  ClayTUI.destroy
end

main

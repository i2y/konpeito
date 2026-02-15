# Ractor Extended Features — JVM Backend
#
# Demonstrates: named Ractors, Ractor-local storage,
# Ractor.make_shareable/shareable?, monitor/unmonitor
#
# Usage:
#   bundle exec ruby -Ilib bin/konpeito build --target jvm --run examples/jvm_ractor_extended.rb

# --- 1. Named Ractors ---
puts "=== Named Ractors ==="
r = Ractor.new(name: "worker-1") { 42 }
puts r.name
r.join

# --- 2. Ractor-local storage ---
puts "=== Local Storage ==="
Ractor[:request_id] = "abc-123"
Ractor[:counter] = 100
puts Ractor[:request_id]
puts Ractor[:counter]

# --- 3. Local storage isolation between Ractors ---
puts "=== Local Storage Isolation ==="
Ractor[:color] = "red"

r = Ractor.new {
  Ractor[:color] = "blue"
  Ractor[:color]
}
child_color = r.value
puts child_color
puts Ractor[:color]

# --- 4. Ractor.make_shareable / shareable? ---
puts "=== Shareable ==="
obj = "hello"
shared = Ractor.make_shareable(obj)
puts shared
if Ractor.shareable?(shared)
  puts "shareable"
end

# --- 5. Monitor: death notification ---
puts "=== Monitor ==="
mon_port = Ractor::Port.new
worker = Ractor.new(name: "monitored") { 99 }
worker.monitor(mon_port)
worker.join
notification = mon_port.receive
puts notification[1] == nil ? "normal_exit" : "error"

# --- 6. Unmonitor: cancel notification ---
puts "=== Unmonitor ==="
mon2 = Ractor::Port.new
r2 = Ractor.new { 1 }
r2.monitor(mon2)
r2.unmonitor(mon2)
r2.join
puts "no_notification"

# --- 7. Named workers with local storage ---
puts "=== Named Workers ==="
result_port = Ractor::Port.new

w1 = Ractor.new(name: "adder") {
  Ractor[:role] = "add"
  result_port.send(10 + 20)
}
w2 = Ractor.new(name: "multiplier") {
  Ractor[:role] = "mul"
  result_port.send(3 * 4)
}

a = result_port.receive
b = result_port.receive
w1.join
w2.join
puts a + b

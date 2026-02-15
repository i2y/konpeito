# Ractor Example — Ruby 4.0 Ractor on JVM (Virtual Threads)
#
# Usage:
#   bundle exec ruby -Ilib bin/konpeito build --target jvm --run examples/jvm_ractor.rb

# --- 1. Basic: Ractor.new + value ---
puts "=== Basic Ractor ==="
r = Ractor.new { 40 + 2 }
puts r.value

# --- 2. Captures ---
puts "=== Captures ==="
x = 10
y = 20
r = Ractor.new { x + y }
puts r.value

# --- 3. Send / Receive ---
puts "=== Send / Receive ==="
r = Ractor.new {
  a = Ractor.receive
  b = Ractor.receive
  a * b
}
r.send(6)
r.send(7)
puts r.value

# --- 4. Port-based communication ---
puts "=== Port ==="
port = Ractor::Port.new
r = Ractor.new {
  port.send(100)
  port.send(200)
  port.send(300)
}
a = port.receive
b = port.receive
c = port.receive
r.join
puts a + b + c

# --- 5. Request / Reply with two ports ---
puts "=== Request / Reply ==="
request = Ractor::Port.new
reply = Ractor::Port.new

worker = Ractor.new {
  msg = request.receive
  reply.send(msg + 1)
}

request.send(99)
puts reply.receive
worker.join

# --- 6. Ractor.select ---
puts "=== Select ==="
p1 = Ractor::Port.new
p2 = Ractor::Port.new

r = Ractor.new {
  p2.send(42)
}

result = Ractor.select(p1, p2)
r.join
puts result[1]

# --- 7. Multiple workers (fan-out / fan-in) ---
puts "=== Fan-out ==="
result_port = Ractor::Port.new

w1 = Ractor.new { result_port.send(10) }
w2 = Ractor.new { result_port.send(20) }
w3 = Ractor.new { result_port.send(30) }

a = result_port.receive
b = result_port.receive
c = result_port.receive
w1.join
w2.join
w3.join
puts a + b + c

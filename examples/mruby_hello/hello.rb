# mruby standalone Hello World
# Build: konpeito build --target mruby hello.rb
# Run:   ./hello

def main
  puts "Hello from Konpeito mruby standalone!"
  puts "1 + 2 = #{1 + 2}"

  arr = [10, 20, 30]
  sum = 0
  arr.each { |x| sum = sum + x }
  puts "Array sum: #{sum}"
end

main

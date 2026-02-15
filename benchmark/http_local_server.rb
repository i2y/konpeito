# Simple HTTP server for benchmarking
require 'socket'

port = ARGV[0]&.to_i || 18081
server = TCPServer.new('127.0.0.1', port)
puts "Server started on port #{port}"
STDOUT.flush

loop do
  client = server.accept
  request = client.gets
  while (line = client.gets) && line != "\r\n"; end
  client.print "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello, World!"
  client.close
end

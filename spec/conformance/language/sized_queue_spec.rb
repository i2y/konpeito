require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/sizedqueue/*
# SizedQueue for bounded producer-consumer

# Basic push/pop
def test_sized_queue_basic
  sq = SizedQueue.new(3)
  sq.push(1)
  sq.push(2)
  sq.push(3)
  assert_equal(1, sq.pop, "SizedQueue#pop returns first pushed item (FIFO)")
  assert_equal(2, sq.pop, "SizedQueue#pop returns second item")
  assert_equal(3, sq.pop, "SizedQueue#pop returns third item")
end

# Size tracking
def test_sized_queue_size
  sq = SizedQueue.new(5)
  assert_equal(0, sq.size, "SizedQueue#size returns 0 for empty queue")
  sq.push("a")
  sq.push("b")
  assert_equal(2, sq.size, "SizedQueue#size returns number of items")
  sq.pop
  assert_equal(1, sq.size, "SizedQueue#size decreases after pop")
end

# Blocking on full queue
def test_sized_queue_blocks_when_full
  sq = SizedQueue.new(2)
  sq.push(1)
  sq.push(2)

  pushed = false
  t = Thread.new {
    sq.push(3)
    pushed = true
  }

  sleep(0.1)
  assert_false(pushed, "SizedQueue blocks push when at capacity")

  sq.pop
  t.join
  assert_true(pushed, "SizedQueue unblocks push after pop makes room")
end

# Producer-consumer with SizedQueue
def test_sized_queue_producer_consumer
  sq = SizedQueue.new(3)
  results = []

  producer = Thread.new {
    i = 0
    while i < 5
      sq.push(i * 10)
      i = i + 1
    end
  }

  consumer = Thread.new {
    i = 0
    while i < 5
      results.push(sq.pop)
      i = i + 1
    end
  }

  producer.join
  consumer.join

  assert_equal(5, results.length, "producer-consumer processes all items")
  assert_equal(0, results[0], "producer-consumer first item is correct")
  assert_equal(40, results[4], "producer-consumer last item is correct")
end

# Empty check
def test_sized_queue_empty
  sq = SizedQueue.new(3)
  assert_true(sq.empty?, "SizedQueue#empty? returns true for empty queue")
  sq.push(1)
  assert_false(sq.empty?, "SizedQueue#empty? returns false when items present")
  sq.pop
  assert_true(sq.empty?, "SizedQueue#empty? returns true after all items popped")
end

def run_tests
  spec_reset
  test_sized_queue_basic
  test_sized_queue_size
  test_sized_queue_blocks_when_full
  test_sized_queue_producer_consumer
  test_sized_queue_empty
  spec_summary
end

run_tests

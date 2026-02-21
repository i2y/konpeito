require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/thread and core/mutex specs
# All tests are deterministic using join/value for synchronization

def test_thread_new_and_join
  result = nil
  t = Thread.new { result = 42 }
  t.join
  assert_equal(42, result, "Thread.new executes block and join waits")
end

def test_thread_value
  t = Thread.new { 10 + 20 }
  assert_equal(30, t.value, "Thread#value returns block result")
end

def test_thread_value_string
  t = Thread.new { "hello" + " world" }
  assert_equal("hello world", t.value, "Thread#value returns string result")
end

def test_thread_multiple
  t1 = Thread.new { 1 + 1 }
  t2 = Thread.new { 2 + 2 }
  v1 = t1.value
  v2 = t2.value
  assert_equal(2, v1, "first thread returns correct value")
  assert_equal(4, v2, "second thread returns correct value")
end

def test_mutex_synchronize
  counter = 0
  mutex = Mutex.new
  threads = []
  i = 0
  while i < 5
    t = Thread.new { mutex.synchronize { counter = counter + 1 } }
    threads = threads + [t]
    i = i + 1
  end
  threads.each { |t| t.join }
  assert_equal(5, counter, "Mutex.synchronize ensures correct counter with 5 threads")
end

def test_mutex_lock_unlock
  mutex = Mutex.new
  result = nil
  mutex.lock
  result = "locked"
  mutex.unlock
  assert_equal("locked", result, "Mutex lock/unlock basic usage works")
end

def test_thread_with_captures
  x = 10
  t = Thread.new { x + 5 }
  assert_equal(15, t.value, "Thread captures outer variable")
end

def test_thread_join_returns_thread
  t = Thread.new { 42 }
  joined = t.join
  assert_true(joined.is_a?(Thread), "Thread#join returns the thread object")
end

def run_tests
  spec_reset
  test_thread_new_and_join
  test_thread_value
  test_thread_value_string
  test_thread_multiple
  test_mutex_synchronize
  test_mutex_lock_unlock
  test_thread_with_captures
  test_thread_join_returns_thread
  spec_summary
end

run_tests

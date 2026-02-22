require_relative "../lib/konpeito_spec"

# Based on ruby/spec core/conditionvariable/*
# ConditionVariable for thread synchronization

# Basic signal/wait
def test_cv_signal_wakes_waiting_thread
  mutex = Mutex.new
  cv = ConditionVariable.new
  result = nil

  t = Thread.new {
    mutex.synchronize {
      cv.wait(mutex)
      result = "woken"
    }
  }

  sleep(0.1)
  mutex.synchronize {
    cv.signal
  }
  t.join

  assert_equal("woken", result, "ConditionVariable#signal wakes waiting thread")
end

# Broadcast wakes all threads
def test_cv_broadcast_wakes_all
  mutex = Mutex.new
  cv = ConditionVariable.new
  count = 0

  threads = []
  i = 0
  while i < 3
    t = Thread.new {
      mutex.synchronize {
        cv.wait(mutex)
        count = count + 1
      }
    }
    threads = threads + [t]
    i = i + 1
  end

  sleep(0.1)
  mutex.synchronize {
    cv.broadcast
  }
  threads.each { |t| t.join }

  assert_equal(3, count, "ConditionVariable#broadcast wakes all waiting threads")
end

# Producer-Consumer pattern
def test_producer_consumer
  mutex = Mutex.new
  cv = ConditionVariable.new
  data = nil
  ready = false

  consumer = Thread.new {
    mutex.synchronize {
      while ready == false
        cv.wait(mutex)
      end
      data
    }
  }

  sleep(0.1)
  mutex.synchronize {
    data = "produced"
    ready = true
    cv.signal
  }

  result = consumer.value
  assert_equal("produced", result, "producer-consumer pattern works with ConditionVariable")
end

# Multiple signal calls
def test_cv_multiple_signals
  mutex = Mutex.new
  cv = ConditionVariable.new
  results = []

  t1 = Thread.new {
    mutex.synchronize {
      cv.wait(mutex)
      results.push("first")
    }
  }

  sleep(0.05)

  t2 = Thread.new {
    mutex.synchronize {
      cv.wait(mutex)
      results.push("second")
    }
  }

  sleep(0.1)

  mutex.synchronize { cv.signal }
  sleep(0.05)
  mutex.synchronize { cv.signal }

  t1.join
  t2.join

  assert_equal(2, results.length, "multiple signal calls wake multiple threads")
end

def run_tests
  spec_reset
  test_cv_signal_wakes_waiting_thread
  test_cv_broadcast_wakes_all
  test_producer_consumer
  test_cv_multiple_signals
  spec_summary
end

run_tests

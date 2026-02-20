$__spec_pass = 0
$__spec_fail = 0

def spec_reset
  $__spec_pass = 0
  $__spec_fail = 0
end

def assert_equal(expected, actual, desc)
  if expected == actual
    $__spec_pass = $__spec_pass + 1
    puts "PASS: " + desc
  else
    $__spec_fail = $__spec_fail + 1
    puts "FAIL: " + desc + " - expected " + expected.to_s + ", got " + actual.to_s
  end
end

def assert_true(value, desc)
  if value
    $__spec_pass = $__spec_pass + 1
    puts "PASS: " + desc
  else
    $__spec_fail = $__spec_fail + 1
    puts "FAIL: " + desc + " - expected truthy, got " + value.to_s
  end
end

def assert_false(value, desc)
  if value
    $__spec_fail = $__spec_fail + 1
    puts "FAIL: " + desc + " - expected falsy, got " + value.to_s
  else
    $__spec_pass = $__spec_pass + 1
    puts "PASS: " + desc
  end
end

def assert_nil(value, desc)
  if value == nil
    $__spec_pass = $__spec_pass + 1
    puts "PASS: " + desc
  else
    $__spec_fail = $__spec_fail + 1
    puts "FAIL: " + desc + " - expected nil, got " + value.to_s
  end
end

def spec_summary
  total = $__spec_pass + $__spec_fail
  puts "SUMMARY: " + $__spec_pass.to_s + " passed, " + $__spec_fail.to_s + " failed, " + total.to_s + " total"
end

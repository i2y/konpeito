# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class JVMTypeResolutionTest < Minitest::Test
  JAVA_CMD = if File.exist?("/opt/homebrew/opt/openjdk@21/bin/java")
               "/opt/homebrew/opt/openjdk@21/bin/java"
             else
               `which java 2>/dev/null`.strip
             end

  def setup
    skip "Java 21+ not found" if JAVA_CMD.empty? || !File.exist?(JAVA_CMD)
    @tmpdir = Dir.mktmpdir("konpeito-jvm-type-test")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  def compile_and_run(source, rbs: nil, name: "test")
    source_file = File.join(@tmpdir, "#{name}.rb")
    File.write(source_file, source)

    rbs_paths = []
    if rbs
      rbs_file = File.join(@tmpdir, "#{name}.rbs")
      File.write(rbs_file, rbs)
      rbs_paths = [rbs_file]
    end

    jar_file = File.join(@tmpdir, "#{name}.jar")

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: jar_file,
      rbs_paths: rbs_paths,
      target: :jvm
    )
    compiler.compile

    assert File.exist?(jar_file), "JAR file should be created: #{jar_file}"

    output = `#{JAVA_CMD} -jar #{jar_file} 2>&1`.strip
    [$?.success?, output]
  end

  # ══════════════════════════════════════════════════════════════════
  # Category P1: HM-Only (No RBS) — Full Pipeline
  # ══════════════════════════════════════════════════════════════════

  def test_e2e_hm_only_integer_arithmetic
    source = <<~RUBY
      def add(a, b)
        a + b
      end
      puts add(3, 5)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def add: (Integer a, Integer b) -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "hm_int_arith")
    assert success, "Should compile and run: #{output}"
    assert_equal "8", output
  end

  def test_e2e_hm_only_string_concat
    source = <<~RUBY
      def greet(name)
        "Hello, " + name
      end
      puts greet("World")
    RUBY
    rbs = <<~RBS
      module TopLevel
        def greet: (String name) -> String
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "hm_str_concat")
    assert success, "Should compile and run: #{output}"
    assert_equal "Hello, World", output
  end

  def test_e2e_hm_only_while_loop
    source = <<~RUBY
      def sum_to(n)
        total = 0
        i = 1
        while i <= n
          total = total + i
          i = i + 1
        end
        total
      end
      puts sum_to(10)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def sum_to: (Integer n) -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "hm_while")
    assert success, "Should compile and run: #{output}"
    assert_equal "55", output
  end

  def test_e2e_hm_only_if_else
    source = <<~RUBY
      def classify(n)
        if n > 0
          "positive"
        else
          "non-positive"
        end
      end
      puts classify(5)
      puts classify(-1)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def classify: (Integer n) -> String
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "hm_if_else")
    assert success, "Should compile and run: #{output}"
    assert_equal "positive\nnon-positive", output
  end

  def test_e2e_hm_only_nested_calls
    source = <<~RUBY
      def double(x)
        x * 2
      end
      def quad(x)
        double(double(x))
      end
      puts quad(3)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def double: (Integer x) -> Integer
        def quad: (Integer x) -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "hm_nested")
    assert success, "Should compile and run: #{output}"
    assert_equal "12", output
  end

  def test_e2e_hm_only_recursive
    source = <<~RUBY
      def factorial(n)
        if n <= 1
          1
        else
          n * factorial(n - 1)
        end
      end
      puts factorial(5)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def factorial: (Integer n) -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "hm_recursive")
    assert success, "Should compile and run: #{output}"
    assert_equal "120", output
  end

  def test_e2e_hm_only_class_and_methods
    source = <<~RUBY
      class Counter
        def initialize(start)
          @count = start
        end
        def increment
          @count = @count + 1
        end
        def value
          @count
        end
      end
      c = Counter.new(0)
      c.increment
      c.increment
      c.increment
      puts c.value
    RUBY
    rbs = <<~RBS
      class Counter
        @count: Integer
        def self.new: (Integer start) -> Counter
        def initialize: (Integer start) -> void
        def increment: () -> Integer
        def value: () -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "hm_class")
    assert success, "Should compile and run: #{output}"
    assert_equal "3", output
  end

  def test_e2e_hm_only_block_map
    source = <<~RUBY
      arr = [1, 2, 3, 4, 5]
      doubled = arr.map { |x| x * 2 }
      puts doubled.length
    RUBY

    success, output = compile_and_run(source, name: "hm_block_map")
    assert success, "Should compile and run: #{output}"
    assert_equal "5", output
  end

  # ══════════════════════════════════════════════════════════════════
  # Category P2: RBS Refining HM — Full Pipeline
  # ══════════════════════════════════════════════════════════════════

  def test_e2e_rbs_refines_params
    source = <<~RUBY
      def compute(a, b, c)
        (a + b) * c
      end
      puts compute(2, 3, 4)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def compute: (Integer a, Integer b, Integer c) -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "rbs_params")
    assert success, "Should compile and run: #{output}"
    assert_equal "20", output
  end

  def test_e2e_rbs_native_class_fields
    source = <<~RUBY
      class Vec2
        def initialize
          @x = 0.0
          @y = 0.0
        end
        def x
          @x
        end
        def x=(v)
          @x = v
        end
        def y
          @y
        end
        def y=(v)
          @y = v
        end
        def length_squared
          @x * @x + @y * @y
        end
      end
      v = Vec2.new
      v.x = 3.0
      v.y = 4.0
      puts v.length_squared
    RUBY
    rbs = <<~RBS
      class Vec2
        @x: Float
        @y: Float
        def self.new: () -> Vec2
        def initialize: () -> void
        def x: () -> Float
        def x=: (Float v) -> Float
        def y: () -> Float
        def y=: (Float v) -> Float
        def length_squared: () -> Float
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "rbs_native")
    assert success, "Should compile and run: #{output}"
    assert_equal "25.0", output
  end

  def test_e2e_rbs_block_type
    source = <<~RUBY
      arr = [1, 2, 3, 4, 5]
      sum = arr.reduce(0) { |acc, x| acc + x }
      puts sum
    RUBY

    success, output = compile_and_run(source, name: "rbs_block")
    assert success, "Should compile and run: #{output}"
    assert_equal "15", output
  end

  # ══════════════════════════════════════════════════════════════════
  # Category P3: Combined Features — Full Pipeline
  # ══════════════════════════════════════════════════════════════════

  def test_e2e_class_with_array_methods
    source = <<~RUBY
      class Stats
        def initialize
          @items = []
        end
        def add(item)
          @items.push(item)
        end
        def count
          @items.length
        end
      end
      s = Stats.new
      s.add(10)
      s.add(20)
      s.add(30)
      puts s.count
    RUBY
    rbs = <<~RBS
      class Stats
        @items: Array
        def self.new: () -> Stats
        def initialize: () -> void
        def add: (Integer item) -> Array
        def count: () -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "combined_class_arr")
    assert success, "Should compile and run: #{output}"
    assert_equal "3", output
  end

  def test_e2e_block_with_capture
    source = <<~RUBY
      offset = 100
      arr = [1, 2, 3]
      result = arr.map { |x| x + offset }
      puts result.length
    RUBY

    success, output = compile_and_run(source, name: "block_capture")
    assert success, "Should compile and run: #{output}"
    assert_equal "3", output
  end

  def test_e2e_case_when
    source = <<~RUBY
      def describe(n)
        case n
        when 1 then "one"
        when 2 then "two"
        when 3 then "three"
        else "other"
        end
      end
      puts describe(1)
      puts describe(2)
      puts describe(99)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def describe: (Integer n) -> String
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "case_when")
    assert success, "Should compile and run: #{output}"
    assert_equal "one\ntwo\nother", output
  end

  def test_e2e_inheritance
    source = <<~RUBY
      class Animal
        def speak
          "..."
        end
      end
      class Dog < Animal
        def speak
          "Woof"
        end
      end
      d = Dog.new
      puts d.speak
    RUBY
    rbs = <<~RBS
      class Animal
        def self.new: () -> Animal
        def speak: () -> String
      end
      class Dog < Animal
        def self.new: () -> Dog
        def speak: () -> String
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "inheritance")
    assert success, "Should compile and run: #{output}"
    assert_equal "Woof", output
  end

  def test_e2e_logical_operators
    source = <<~RUBY
      def check(a, b)
        if a > 0 && b > 0
          "both positive"
        else
          "not both"
        end
      end
      puts check(1, 2)
      puts check(-1, 2)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def check: (Integer a, Integer b) -> String
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "logical_ops")
    assert success, "Should compile and run: #{output}"
    assert_equal "both positive\nnot both", output
  end

  def test_e2e_string_interpolation
    source = <<~RUBY
      name = "World"
      age = 42
      puts "Hello, \#{name}! Age: \#{age}"
    RUBY

    success, output = compile_and_run(source, name: "str_interp")
    assert success, "Should compile and run: #{output}"
    assert_equal "Hello, World! Age: 42", output
  end

  def test_e2e_compound_assignment
    source = <<~RUBY
      def accumulate(n)
        total = 0
        i = 1
        while i <= n
          total += i
          i += 1
        end
        total
      end
      puts accumulate(10)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def accumulate: (Integer n) -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "compound_assign")
    assert success, "Should compile and run: #{output}"
    assert_equal "55", output
  end

  def test_e2e_array_select
    source = <<~RUBY
      arr = [1, 2, 3, 4, 5, 6]
      evens = arr.select { |x| x % 2 == 0 }
      puts evens.length
    RUBY

    success, output = compile_and_run(source, name: "arr_select")
    assert success, "Should compile and run: #{output}"
    assert_equal "3", output
  end

  def test_e2e_multi_assign
    source = <<~RUBY
      arr = [10, 20, 30]
      a, b, c = arr
      puts a
      puts b
      puts c
    RUBY

    success, output = compile_and_run(source, name: "multi_assign")
    assert success, "Should compile and run: #{output}"
    assert_equal "10\n20\n30", output
  end

  def test_e2e_while_loop_sum
    # Range#each is not yet supported on JVM backend, use while loop
    source = <<~RUBY
      def sum_range(n)
        total = 0
        i = 1
        while i <= n
          total = total + i
          i = i + 1
        end
        total
      end
      puts sum_range(5)
    RUBY
    rbs = <<~RBS
      module TopLevel
        def sum_range: (Integer n) -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "while_sum")
    assert success, "Should compile and run: #{output}"
    assert_equal "15", output
  end

  def test_e2e_module_method
    source = <<~RUBY
      module MathHelper
        def self.square(x)
          x * x
        end
      end
      puts MathHelper.square(7)
    RUBY
    rbs = <<~RBS
      module MathHelper
        def self.square: (Integer x) -> Integer
      end
    RBS

    success, output = compile_and_run(source, rbs: rbs, name: "module_method")
    assert success, "Should compile and run: #{output}"
    assert_equal "49", output
  end
end

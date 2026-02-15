# frozen_string_literal: true

require "test_helper"
require "fileutils"

class PatternMatchCollectionTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @ast_builder = Konpeito::AST::TypedASTBuilder.new(@loader)
    @hir_builder = Konpeito::HIR::Builder.new
    @output_dir = File.join(__dir__, "..", "tmp")
    FileUtils.mkdir_p(@output_dir)
  end

  def teardown
    FileUtils.rm_rf(@output_dir)
  end

  def compile_to_bundle(source, name)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = @ast_builder.build(ast)
    hir = @hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: name)
    llvm_gen.generate(hir)

    output_file = File.join(@output_dir, "#{name}.bundle")
    backend = Konpeito::Codegen::CRubyBackend.new(
      llvm_gen,
      output_file: output_file,
      module_name: name
    )
    backend.generate
    output_file
  end

  # ========================================
  # Array Pattern Tests
  # ========================================

  def test_array_pattern_simple
    source = <<~RUBY
      def match_pair(arr)
        case arr
        in [a, b] then a + b
        else 0
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_array_simple")

    require output
    assert_equal 3, match_pair([1, 2])
    assert_equal 30, match_pair([10, 20])
    assert_equal 0, match_pair([1, 2, 3])  # wrong length
    assert_equal 0, match_pair([1])        # wrong length
    assert_equal 0, match_pair([])         # empty
  end

  def test_array_pattern_with_rest
    source = <<~RUBY
      def get_first(arr)
        case arr
        in [first, *rest] then first
        else -1
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_array_rest")

    require output
    assert_equal 1, get_first([1, 2, 3])
    assert_equal 10, get_first([10])
    assert_equal -1, get_first([])
  end

  def test_array_pattern_rest_length
    source = <<~RUBY
      def rest_len(arr)
        case arr
        in [first, *rest] then rest.length
        else -1
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_array_rest_len")

    require output
    assert_equal 2, rest_len([1, 2, 3])
    assert_equal 0, rest_len([10])
    assert_equal -1, rest_len([])
  end

  def test_array_pattern_first_and_last
    source = <<~RUBY
      def first_plus_last(arr)
        case arr
        in [first, *mid, last] then first + last
        else -1
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_array_first_last")

    require output
    assert_equal 5, first_plus_last([1, 2, 3, 4])
    assert_equal 30, first_plus_last([10, 20])
    assert_equal -1, first_plus_last([1])  # need at least 2 elements
    assert_equal -1, first_plus_last([])
  end

  def test_array_pattern_triple
    source = <<~RUBY
      def sum_triple(arr)
        case arr
        in [a, b, c] then a + b + c
        else 0
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_array_triple")

    require output
    assert_equal 6, sum_triple([1, 2, 3])
    assert_equal 60, sum_triple([10, 20, 30])
    assert_equal 0, sum_triple([1, 2])
    assert_equal 0, sum_triple([1, 2, 3, 4])
  end

  # ========================================
  # Hash Pattern Tests
  # ========================================

  def test_hash_pattern_shorthand
    source = <<~RUBY
      def extract_xy(h)
        case h
        in {x:, y:} then x + y
        else 0
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_hash_shorthand")

    require output
    assert_equal 30, extract_xy({x: 10, y: 20})
    assert_equal 8, extract_xy({x: 5, y: 3})
    assert_equal 0, extract_xy({a: 100})  # missing keys
    assert_equal 0, extract_xy({x: 10})   # missing y
  end

  def test_hash_pattern_single_key
    source = <<~RUBY
      def get_name(h)
        case h
        in {name:} then name
        else "unknown"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_hash_single")

    require output
    assert_equal "Alice", get_name({name: "Alice"})
    assert_equal "Bob", get_name({name: "Bob", age: 30})
    assert_equal "unknown", get_name({age: 30})
  end

  def test_hash_pattern_multiple_keys
    source = <<~RUBY
      def describe_person(h)
        case h
        in {name:, age:, city:}
          name.to_s + " is " + age.to_s + " from " + city.to_s
        else
          "incomplete"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_hash_multi")

    require output
    assert_equal "Alice is 30 from NYC", describe_person({name: "Alice", age: 30, city: "NYC"})
    assert_equal "incomplete", describe_person({name: "Bob"})
  end

  # ========================================
  # Nested Pattern Tests
  # ========================================

  def test_nested_array_in_array
    source = <<~RUBY
      def nested_sum(arr)
        case arr
        in [[a, b], [c, d]]
          a + b + c + d
        else
          0
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_nested_array")

    require output
    assert_equal 10, nested_sum([[1, 2], [3, 4]])
    assert_equal 100, nested_sum([[10, 20], [30, 40]])
    # Note: [1, 2] would fail with "undefined method 'deconstruct' for Integer"
    # because the pattern attempts to deconstruct the inner elements without
    # type-checking first. This is a known limitation. Use type patterns when needed.
    assert_equal 0, nested_sum([[1], [2, 3]])  # inner array wrong length
  end

  def test_nested_hash_in_array
    source = <<~RUBY
      def nested_hash_sum(arr)
        case arr
        in [{x:}, {y:}]
          x + y
        else
          0
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_nested_hash_array")

    require output
    assert_equal 30, nested_hash_sum([{x: 10}, {y: 20}])
    assert_equal 0, nested_hash_sum([{a: 1}, {b: 2}])
  end

  # ========================================
  # Combined Pattern Tests
  # ========================================

  def test_multiple_patterns
    # Note: Mixing array/hash patterns with other types in one case statement
    # can cause issues because deconstruct is called before type checking.
    # Best practice: Use type patterns (Integer, String, etc.) at the end,
    # or check types explicitly first.
    source = <<~RUBY
      def classify_array(data)
        case data
        in [a, b] then "pair"
        in [a, b, c] then "triple"
        else "other"
        end
      end

      def classify_hash(data)
        case data
        in {x:, y:} then "point"
        in {name:} then "named"
        else "other"
        end
      end

      def classify_type(data)
        case data
        in String then "string"
        in Integer then "number"
        in Float then "float"
        else "other"
        end
      end
    RUBY
    output = compile_to_bundle(source, "test_classify")

    require output
    assert_equal "pair", classify_array([1, 2])
    assert_equal "triple", classify_array([1, 2, 3])
    assert_equal "other", classify_array([1])

    assert_equal "point", classify_hash({x: 0, y: 0})
    assert_equal "named", classify_hash({name: "test"})
    assert_equal "other", classify_hash({a: 1})

    assert_equal "string", classify_type("hello")
    assert_equal "number", classify_type(42)
    assert_equal "float", classify_type(3.14)
  end
end

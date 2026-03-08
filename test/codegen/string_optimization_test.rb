# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class StringOptimizationTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # --- Step 1a: rb_obj_as_string for string interpolation ---

  def test_interpolation_with_integer_to_s
    source = <<~RUBY
      def interp_int(n)
        "value: \#{n}"
      end
    RUBY

    assert_equal "value: 42", compile_and_run(source, "interp_int(42)")
  end

  def test_interpolation_with_string_no_to_s
    # String parts should pass through without calling to_s
    source = <<~RUBY
      def interp_str(s)
        "hello \#{s}!"
      end
    RUBY

    assert_equal "hello world!", compile_and_run(source, 'interp_str("world")')
  end

  def test_interpolation_with_float_to_s
    source = <<~RUBY
      def interp_float(f)
        "pi is \#{f}"
      end
    RUBY

    assert_equal "pi is 3.14", compile_and_run(source, "interp_float(3.14)")
  end

  def test_interpolation_with_nil_to_s
    source = <<~RUBY
      def interp_nil
        "value: \#{nil}"
      end
    RUBY

    assert_equal "value: ", compile_and_run(source, "interp_nil")
  end

  def test_interpolation_with_bool_to_s
    source = <<~RUBY
      def interp_bool(b)
        "flag: \#{b}"
      end
    RUBY

    assert_equal "flag: true", compile_and_run(source, "interp_bool(true)")
  end

  # --- Step 1b: Static length buffer pre-allocation (no dynamic scan) ---

  def test_interpolation_multiple_static_parts
    source = <<~RUBY
      def multi_static(name, age)
        "Name: \#{name}, Age: \#{age}, Done."
      end
    RUBY

    assert_equal "Name: Alice, Age: 30, Done.", compile_and_run(source, 'multi_static("Alice", 30)')
  end

  def test_interpolation_long_static_parts
    source = <<~RUBY
      def long_static(x)
        "This is a very long prefix string that tests buffer pre-allocation: \#{x} and a long suffix string."
      end
    RUBY

    assert_equal "This is a very long prefix string that tests buffer pre-allocation: 99 and a long suffix string.",
      compile_and_run(source, "long_static(99)")
  end

  # --- Step 3: BUILTIN_METHODS String methods ---

  def test_string_times
    source = <<~RUBY
      def str_repeat(s)
        s * 3
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_repeat: (String s) -> String
      end
    RBS

    assert_equal "abcabcabc", compile_and_run_typed(source, rbs, 'str_repeat("abc")')
  end

  def test_string_freeze
    source = <<~RUBY
      def str_frz(s)
        s.freeze
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_frz: (String s) -> String
      end
    RBS

    result = compile_and_run_typed(source, rbs, 'str_frz("hello")')
    assert_equal "hello", result
  end

  def test_string_replace
    source = <<~RUBY
      def str_repl(s, r)
        s.replace(r)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_repl: (String s, String r) -> String
      end
    RBS

    assert_equal "world", compile_and_run_typed(source, rbs, 'str_repl("hello", "world")')
  end

  def test_string_succ
    source = <<~RUBY
      def str_succ(s)
        s.succ
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_succ: (String s) -> String
      end
    RBS

    assert_equal "abd", compile_and_run_typed(source, rbs, 'str_succ("abc")')
  end

  def test_string_next
    source = <<~RUBY
      def str_next(s)
        s.next
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_next: (String s) -> String
      end
    RBS

    assert_equal "abd", compile_and_run_typed(source, rbs, 'str_next("abc")')
  end

  def test_string_inspect
    source = <<~RUBY
      def str_insp(s)
        s.inspect
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_insp: (String s) -> String
      end
    RBS

    assert_equal '"hello"', compile_and_run_typed(source, rbs, 'str_insp("hello")')
  end

  # --- Step 4: String#empty? inlining ---

  def test_string_empty_true
    source = <<~RUBY
      def str_empty(s)
        s.empty?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_empty: (String s) -> bool
      end
    RBS

    assert_equal true, compile_and_run_typed(source, rbs, 'str_empty("")')
  end

  def test_string_empty_false
    source = <<~RUBY
      def str_not_empty(s)
        s.empty?
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_not_empty: (String s) -> bool
      end
    RBS

    assert_equal false, compile_and_run_typed(source, rbs, 'str_not_empty("hello")')
  end

  def test_string_empty_in_condition
    source = <<~RUBY
      def empty_check(s)
        if s.empty?
          "empty"
        else
          "not empty"
        end
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def empty_check: (String s) -> String
      end
    RBS

    assert_equal "empty", compile_and_run_typed(source, rbs, 'empty_check("")')
    assert_equal "not empty", compile_and_run_typed(source, rbs, 'empty_check("x")')
  end

  # --- Step 5: String#[] two-arg form (rb_str_substr) ---

  def test_string_substr_two_args
    source = <<~RUBY
      def str_sub(s)
        s[0, 5]
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_sub: (String s) -> String
      end
    RBS

    assert_equal "hello", compile_and_run_typed(source, rbs, 'str_sub("hello world")')
  end

  def test_string_substr_middle
    source = <<~RUBY
      def str_mid(s)
        s[6, 5]
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_mid: (String s) -> String
      end
    RBS

    assert_equal "world", compile_and_run_typed(source, rbs, 'str_mid("hello world")')
  end

  def test_string_substr_with_variables
    source = <<~RUBY
      def str_sub_var(s, start, len)
        s[start, len]
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_sub_var: (String s, Integer start, Integer len) -> String
      end
    RBS

    assert_equal "llo", compile_and_run_typed(source, rbs, 'str_sub_var("hello", 2, 3)')
  end

  # --- Step 6: String#split optimization ---

  def test_string_split_literal
    source = <<~RUBY
      def str_split_lit(s)
        s.split(",")
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_split_lit: (String s) -> Array
      end
    RBS

    assert_equal ["a", "b", "c"], compile_and_run_typed(source, rbs, 'str_split_lit("a,b,c")')
  end

  def test_string_split_space
    source = <<~RUBY
      def str_split_sp(s)
        s.split(" ")
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_split_sp: (String s) -> Array
      end
    RBS

    assert_equal ["hello", "world"], compile_and_run_typed(source, rbs, 'str_split_sp("hello world")')
  end

  def test_string_split_dynamic_sep
    source = <<~RUBY
      def str_split_dyn(s, sep)
        s.split(sep)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def str_split_dyn: (String s, String sep) -> Array
      end
    RBS

    assert_equal ["x", "y", "z"], compile_and_run_typed(source, rbs, 'str_split_dyn("x-y-z", "-")')
  end

  # --- LLVM IR verification tests ---

  def test_ir_uses_rb_obj_as_string
    ir = compile_to_ir(<<~RUBY)
      def interp_ir(n)
        "val: \#{n}"
      end
    RUBY

    assert_includes ir, "rb_obj_as_string"
    refute_match(/rb_funcallv.*to_s/, ir)
  end

  def test_ir_uses_rb_str_strlen_for_empty
    ir = compile_to_ir_typed(<<~RUBY, <<~RBS)
      def empty_ir(s)
        s.empty?
      end
    RUBY
      module TopLevel
        def empty_ir: (String s) -> bool
      end
    RBS

    assert_includes ir, "rb_str_strlen"
  end

  private

  def compile_and_run(source, call_expr)
    source_file = File.join(@tmp_dir, "test.rb")
    output_file = File.join(@tmp_dir, "test#{SHARED_EXT}")

    File.write(source_file, source)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file
    )
    compiler.compile

    require output_file

    eval(call_expr) # rubocop:disable Security/Eval
  end

  def compile_and_run_typed(source, rbs, call_expr)
    source_file = File.join(@tmp_dir, "test.rb")
    rbs_file = File.join(@tmp_dir, "test.rbs")
    output_file = File.join(@tmp_dir, "test#{SHARED_EXT}")

    File.write(source_file, source)
    File.write(rbs_file, rbs)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file,
      rbs_paths: [rbs_file]
    )
    compiler.compile

    require output_file

    eval(call_expr) # rubocop:disable Security/Eval
  end

  def compile_to_ir(source)
    loader = Konpeito::TypeChecker::RBSLoader.new.load
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    hir_builder = Konpeito::HIR::Builder.new

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = ast_builder.build(ast)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "test_ir")
    llvm_gen.generate(hir)
    llvm_gen.to_ir
  end

  def compile_to_ir_typed(source, rbs)
    rbs_file = File.join(@tmp_dir, "test_ir.rbs")
    File.write(rbs_file, rbs)

    loader = Konpeito::TypeChecker::RBSLoader.new.load(rbs_paths: [rbs_file])
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    hir_builder = Konpeito::HIR::Builder.new

    ast = Konpeito::Parser::PrismAdapter.parse(source)
    typed_ast = ast_builder.build(ast)
    hir = hir_builder.build(typed_ast)

    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(module_name: "test_ir_typed")
    llvm_gen.generate(hir)
    llvm_gen.to_ir
  end
end

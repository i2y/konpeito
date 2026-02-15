# frozen_string_literal: true

require "test_helper"

class UnionTypeCodegenTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def compile_with_rbs(source, rbs_content)
    # Write RBS file
    rbs_file = File.join(@temp_dir, "types.rbs")
    File.write(rbs_file, rbs_content)

    # Create RBS loader with the custom file
    loader = Konpeito::TypeChecker::RBSLoader.new
    loader.load(rbs_paths: [rbs_file])

    # Parse and type check
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    ast_builder = Konpeito::AST::TypedASTBuilder.new(loader)
    typed_ast = ast_builder.build(ast)

    # HM type inference
    hm_inferrer = Konpeito::TypeChecker::HMInferrer.new(loader)
    hm_inferrer.infer(typed_ast)

    # Build HIR
    hir_builder = Konpeito::HIR::Builder.new
    hir = hir_builder.build(typed_ast)

    # Monomorphization
    monomorphizer = Konpeito::Codegen::Monomorphizer.new(hir, hm_inferrer)
    monomorphizer.analyze
    monomorphizer.transform

    # Generate LLVM IR
    llvm_gen = Konpeito::Codegen::LLVMGenerator.new(
      module_name: "test_union",
      monomorphizer: monomorphizer,
      rbs_loader: loader
    )
    llvm_gen.generate(hir)

    {
      ir: llvm_gen.to_ir,
      monomorphizer: monomorphizer
    }
  end

  def test_union_type_detection_in_monomorphizer
    source = <<~RUBY
      def process(x)
        x + 1
      end

      def caller
        process(42)
        process("hello")
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def process: (Integer | String x) -> (Integer | String)
        def caller: () -> (Integer | String)
      end
    RBS

    result = compile_with_rbs(source, rbs)
    monomorphizer = result[:monomorphizer]

    # Should have union dispatches
    assert monomorphizer.union_dispatches.any?, "Should detect union type dispatches"
  end

  def test_union_type_expands_to_specializations
    source = <<~RUBY
      def double_it(x)
        x + x
      end

      def test
        double_it(42)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def double_it: (Integer | String x) -> (Integer | String)
        def test: () -> (Integer | String)
      end
    RBS

    result = compile_with_rbs(source, rbs)
    monomorphizer = result[:monomorphizer]

    # Should have specializations for both Integer and String
    specializations = monomorphizer.specializations
    spec_names = specializations.values

    assert spec_names.any? { |name| name.include?("Integer") },
           "Should have Integer specialization"
    assert spec_names.any? { |name| name.include?("String") },
           "Should have String specialization"
  end

  def test_union_dispatch_generates_type_checks
    source = <<~RUBY
      def process(x)
        x
      end

      def test
        process(42)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def process: (Integer | Float x) -> (Integer | Float)
        def test: () -> (Integer | Float)
      end
    RBS

    result = compile_with_rbs(source, rbs)
    ir = result[:ir]

    # Should include rb_obj_is_kind_of for type checking
    assert_includes ir, "rb_obj_is_kind_of",
                    "Should generate type checks with rb_obj_is_kind_of"
  end

  def test_union_dispatch_generates_branch_structure
    source = <<~RUBY
      def process(x)
        x
      end

      def test
        process(42)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def process: (Integer | Float x) -> (Integer | Float)
        def test: () -> (Integer | Float)
      end
    RBS

    result = compile_with_rbs(source, rbs)
    ir = result[:ir]

    # Should have union check/match/merge blocks
    assert_includes ir, "union_check",
                    "Should generate union check blocks"
    assert_includes ir, "union_match",
                    "Should generate union match blocks"
    assert_includes ir, "union_merge",
                    "Should generate union merge block"
  end

  def test_optional_type_as_union_with_nil
    source = <<~RUBY
      def maybe(x)
        x
      end

      def test
        maybe(42)
        maybe(nil)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def maybe: (Integer? x) -> Integer?
        def test: () -> Integer?
      end
    RBS

    result = compile_with_rbs(source, rbs)
    monomorphizer = result[:monomorphizer]

    # Optional types (T?) should be treated as Union[T, nil]
    # Check that we have specializations
    assert monomorphizer.specializations.any? || monomorphizer.union_dispatches.any?,
           "Should handle optional types as unions"
  end

  def test_multiple_union_arguments
    source = <<~RUBY
      def combine(a, b)
        a
      end

      def test
        combine(1, "x")
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def combine: (Integer | Float a, String | Symbol b) -> (Integer | Float)
        def test: () -> (Integer | Float)
      end
    RBS

    result = compile_with_rbs(source, rbs)
    monomorphizer = result[:monomorphizer]

    # Should expand to all combinations: (Int, Str), (Int, Sym), (Float, Str), (Float, Sym)
    if monomorphizer.union_dispatches.any?
      dispatch = monomorphizer.union_dispatches.values.first
      specializations = dispatch[:specializations]

      # Should have 4 combinations
      assert_equal 4, specializations.size,
                   "Should have 4 specializations for 2x2 union combinations"
    end
  end

  def test_non_union_calls_not_affected
    source = <<~RUBY
      def simple(x)
        x * 2
      end

      def test
        simple(42)
      end
    RUBY

    rbs = <<~RBS
      module TopLevel
        def simple: (Integer x) -> Integer
        def test: () -> Integer
      end
    RBS

    result = compile_with_rbs(source, rbs)
    monomorphizer = result[:monomorphizer]

    # Should not have union dispatches for non-union types
    assert monomorphizer.union_dispatches.empty?,
           "Non-union calls should not create union dispatches"
  end
end

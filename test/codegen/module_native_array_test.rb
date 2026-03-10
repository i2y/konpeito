# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class ModuleNativeArrayTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_module_native_array_basic_get_set
    source = <<~RUBY
      module MnaStorage1
      end

      def mna_main1
        MnaStorage1.data[0] = 10
        MnaStorage1.data[1] = 20
        MnaStorage1.data[2] = 30
        MnaStorage1.data[3] = 40
        MnaStorage1.data[0] + MnaStorage1.data[1] + MnaStorage1.data[2] + MnaStorage1.data[3]
      end
    RUBY

    result = compile_and_run(source, "mna_main1", <<~RBS)
      module MnaStorage1
        @data: NativeArray[Integer, 4]
      end

      module TopLevel
        def mna_main1: () -> Integer
      end
    RBS

    assert_equal 100, result
  end

  def test_module_native_array_persistence_across_functions
    source = <<~RUBY
      module MnaState2
      end

      def mna_store2
        MnaState2.counter[0] = 42
        0
      end

      def mna_load2
        MnaState2.counter[0]
      end

      def mna_main2
        mna_store2
        mna_load2
      end
    RUBY

    result = compile_and_run(source, "mna_main2", <<~RBS)
      module MnaState2
        @counter: NativeArray[Integer, 1]
      end

      module TopLevel
        def mna_store2: () -> Integer
        def mna_load2: () -> Integer
        def mna_main2: () -> Integer
      end
    RBS

    assert_equal 42, result
  end

  def test_module_native_array_float
    source = <<~RUBY
      module MnaBuf3
      end

      def mna_main3
        MnaBuf3.vals[0] = 1.5
        MnaBuf3.vals[1] = 2.5
        MnaBuf3.vals[2] = 3.0
        MnaBuf3.vals[0] + MnaBuf3.vals[1] + MnaBuf3.vals[2]
      end
    RUBY

    result = compile_and_run(source, "mna_main3", <<~RBS)
      module MnaBuf3
        @vals: NativeArray[Float, 3]
      end

      module TopLevel
        def mna_main3: () -> Float
      end
    RBS

    assert_in_delta 7.0, result, 0.001
  end

  def test_module_native_array_multiple_fields
    source = <<~RUBY
      module MnaGame4
      end

      def mna_main4
        MnaGame4.x[0] = 10
        MnaGame4.x[1] = 20
        MnaGame4.y[0] = 100
        MnaGame4.y[1] = 200
        MnaGame4.x[0] + MnaGame4.x[1] + MnaGame4.y[0] + MnaGame4.y[1]
      end
    RUBY

    result = compile_and_run(source, "mna_main4", <<~RBS)
      module MnaGame4
        @x: NativeArray[Integer, 3]
        @y: NativeArray[Integer, 3]
      end

      module TopLevel
        def mna_main4: () -> Integer
      end
    RBS

    assert_equal 330, result
  end

  def test_module_native_array_loop_access
    source = <<~RUBY
      module MnaArr5
      end

      def mna_main5
        i = 0
        while i < 10
          MnaArr5.data[i] = i * i
          i = i + 1
        end
        MnaArr5.data[0] + MnaArr5.data[9]
      end
    RUBY

    result = compile_and_run(source, "mna_main5", <<~RBS)
      module MnaArr5
        @data: NativeArray[Integer, 10]
      end

      module TopLevel
        def mna_main5: () -> Integer
      end
    RBS

    assert_equal 81, result  # 0*0 + 9*9
  end

  private

  def compile_and_run(source, call_expr, rbs_content)
    @test_counter ||= 0
    @test_counter += 1
    basename = "mna_test_#{Process.pid}_#{@test_counter}"

    source_file = File.join(@tmp_dir, "#{basename}.rb")
    rbs_file = File.join(@tmp_dir, "#{basename}.rbs")
    output_file = File.join(@tmp_dir, "#{basename}#{SHARED_EXT}")

    File.write(source_file, source)
    File.write(rbs_file, rbs_content)

    compiler = Konpeito::Compiler.new(
      source_file: source_file,
      output_file: output_file,
      rbs_paths: [rbs_file]
    )
    compiler.compile

    require output_file
    eval(call_expr)
  end
end

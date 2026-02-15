# frozen_string_literal: true

require "test_helper"

class RBSInlinePreprocessorTest < Minitest::Test
  def test_has_inline_rbs_returns_true_for_enabled
    source = <<~RUBY
      # rbs_inline: enabled
      class Foo
      end
    RUBY

    assert Konpeito::RBSInline::Preprocessor.has_inline_rbs?(source)
  end

  def test_has_inline_rbs_returns_false_for_disabled
    source = <<~RUBY
      class Foo
      end
    RUBY

    refute Konpeito::RBSInline::Preprocessor.has_inline_rbs?(source)
  end

  def test_extract_konpeito_annotations_for_class
    preprocessor = Konpeito::RBSInline::Preprocessor.new
    source = <<~RUBY
      # rbs_inline: enabled
      # @rbs %a{native}
      class Point
        # @rbs @x: Float
        # @rbs @y: Float
      end
    RUBY

    annotations = preprocessor.send(:extract_konpeito_annotations, source)

    assert_includes annotations.keys, "Point"
    assert_includes annotations["Point"], "%a{native}"
  end

  def test_extract_konpeito_annotations_for_method
    preprocessor = Konpeito::RBSInline::Preprocessor.new
    source = <<~RUBY
      # rbs_inline: enabled
      class MathLib
        # @rbs %a{cfunc: "sin"}
        def self.sin(x)
        end
      end
    RUBY

    annotations = preprocessor.send(:extract_konpeito_annotations, source)

    assert_includes annotations.keys, "MathLib.sin"
    assert_includes annotations["MathLib.sin"], '%a{cfunc: "sin"}'
  end

  def test_extract_konpeito_annotations_for_module
    preprocessor = Konpeito::RBSInline::Preprocessor.new
    source = <<~RUBY
      # rbs_inline: enabled
      # @rbs %a{ffi: "libm"}
      module MathLib
      end
    RUBY

    annotations = preprocessor.send(:extract_konpeito_annotations, source)

    assert_includes annotations.keys, "MathLib"
    assert_includes annotations["MathLib"], '%a{ffi: "libm"}'
  end

  def test_find_current_context
    preprocessor = Konpeito::RBSInline::Preprocessor.new
    source = <<~RUBY
      module Outer
        class Inner
          def foo
          end
        end
      end
    RUBY

    lines = source.lines
    # Line index 2 is "class Inner"
    # Line index 3 is "def foo"
    context = preprocessor.send(:find_current_context, lines, 3)
    assert_equal "Inner", context
  end
end

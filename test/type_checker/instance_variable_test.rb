# frozen_string_literal: true

require "test_helper"

class InstanceVariableTypeTest < Minitest::Test
  def setup
    @loader = Konpeito::TypeChecker::RBSLoader.new.load
    @inferrer = Konpeito::TypeChecker::Inferrer.new(@loader)
  end

  def parse_and_infer(source)
    ast = Konpeito::Parser::PrismAdapter.parse(source)
    @inferrer.infer(ast)
  end

  def test_inferrer_tracks_current_class
    source = <<~RUBY
      class Person
        def initialize
          @name = "Alice"
        end
      end
    RUBY
    parse_and_infer(source)
    # After inference, the class context should have been tracked
    # We can't directly test internal state, but we can verify no errors
    assert_empty @inferrer.errors
  end

  def test_self_type_in_class_context
    # Test that self_type returns the class type when in a class context
    # This is tested indirectly through the inferrer
    source = <<~RUBY
      class MyClass
        def myself
          self
        end
      end
    RUBY
    parse_and_infer(source)
    assert_empty @inferrer.errors
  end

  def test_instance_variable_write_tracking
    source = <<~RUBY
      class Counter
        def initialize
          @count = 0
        end

        def increment
          @count = @count + 1
        end
      end
    RUBY
    parse_and_infer(source)
    assert_empty @inferrer.errors
  end

  def test_class_hierarchy_for_internal_types
    # Test the CLASS_HIERARCHY constant
    hierarchy = Konpeito::TypeChecker::Types::ClassInstance::CLASS_HIERARCHY

    # Integer is a subtype of Numeric
    assert_includes hierarchy[:Integer], :Numeric
    assert_includes hierarchy[:Integer], :Object

    # Float is a subtype of Numeric
    assert_includes hierarchy[:Float], :Numeric

    # RuntimeError is a subtype of StandardError
    assert_includes hierarchy[:RuntimeError], :StandardError
    assert_includes hierarchy[:RuntimeError], :Exception
  end

  def test_native_field_to_type_conversion
    # Test the native_field_to_type helper
    int_type = @inferrer.send(:native_field_to_type, :i64)
    assert_equal :Integer, int_type.name

    float_type = @inferrer.send(:native_field_to_type, :double)
    assert_equal :Float, float_type.name

    bool_type = @inferrer.send(:native_field_to_type, :bool)
    assert_equal Konpeito::TypeChecker::Types::BOOL, bool_type
  end
end

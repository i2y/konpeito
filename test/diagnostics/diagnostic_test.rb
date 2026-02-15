# frozen_string_literal: true

require_relative "../test_helper"
require "prism"
require "tempfile"

class DiagnosticTest < Minitest::Test
  def setup
    @sample_source = <<~RUBY
      def add(a, b)
        a + b
      end

      result = add(1, "two")
    RUBY

    @temp_file = Tempfile.new(["test", ".rb"])
    @temp_file.write(@sample_source)
    @temp_file.close
  end

  def teardown
    @temp_file.unlink if @temp_file
  end

  def test_source_span_creation
    span = Konpeito::Diagnostics::SourceSpan.new(
      file_path: @temp_file.path,
      start_line: 5,
      start_column: 10,
      end_line: 5,
      end_column: 25
    )

    assert_equal @temp_file.path, span.file_path
    assert_equal 5, span.start_line
    assert_equal 10, span.start_column
  end

  def test_source_span_from_prism_location
    ast = Prism.parse(@sample_source).value
    call_node = ast.statements.body.last.value  # add(1, "two")

    span = Konpeito::Diagnostics::SourceSpan.from_prism_location(
      call_node.location,
      file_path: @temp_file.path,
      source: @sample_source
    )

    assert_equal @temp_file.path, span.file_path
    assert_equal 5, span.start_line
  end

  def test_source_span_snippet
    span = Konpeito::Diagnostics::SourceSpan.new(
      file_path: @temp_file.path,
      start_line: 5,
      start_column: 10,
      end_line: 5,
      end_column: 25,
      source: @sample_source
    )

    snippet = span.snippet(context_lines: 1)
    assert snippet.is_a?(Array)
    assert snippet.any? { |line| line[:highlight] }
  end

  def test_diagnostic_type_mismatch
    span = Konpeito::Diagnostics::SourceSpan.new(
      file_path: @temp_file.path,
      start_line: 5,
      start_column: 10,
      source: @sample_source
    )

    diagnostic = Konpeito::Diagnostics::Diagnostic.type_mismatch(
      expected: "Integer",
      found: "String",
      span: span
    )

    assert diagnostic.error?
    assert_equal "E001", diagnostic.code
    assert_equal "type mismatch", diagnostic.message
  end

  def test_diagnostic_undefined_variable
    span = Konpeito::Diagnostics::SourceSpan.new(
      file_path: @temp_file.path,
      start_line: 1,
      start_column: 0,
      source: @sample_source
    )

    diagnostic = Konpeito::Diagnostics::Diagnostic.undefined_variable(
      name: "foo",
      span: span,
      similar: "food"
    )

    assert diagnostic.error?
    assert_equal "E004", diagnostic.code
    assert_includes diagnostic.suggestions, "did you mean `food`?"
  end

  def test_diagnostic_circular_dependency
    span = Konpeito::Diagnostics::SourceSpan.new(
      file_path: "a.rb",
      start_line: 1,
      start_column: 0
    )

    diagnostic = Konpeito::Diagnostics::Diagnostic.circular_dependency(
      cycle: ["a.rb", "b.rb", "a.rb"],
      span: span
    )

    assert diagnostic.error?
    assert_equal "E020", diagnostic.code
    assert diagnostic.notes.any? { |n| n.include?("a.rb -> b.rb -> a.rb") }
  end

  def test_diagnostic_file_not_found
    span = Konpeito::Diagnostics::SourceSpan.new(
      file_path: "main.rb",
      start_line: 1,
      start_column: 0
    )

    diagnostic = Konpeito::Diagnostics::Diagnostic.file_not_found(
      path: "missing.rb",
      span: span
    )

    assert diagnostic.error?
    assert_equal "E021", diagnostic.code
  end

  def test_diagnostic_severities
    error = Konpeito::Diagnostics::Diagnostic.new(
      severity: :error,
      code: "E001",
      message: "test error"
    )
    assert error.error?
    refute error.warning?

    warning = Konpeito::Diagnostics::Diagnostic.new(
      severity: :warning,
      code: "W001",
      message: "test warning"
    )
    refute warning.error?
    assert warning.warning?
  end
end

class DiagnosticRendererTest < Minitest::Test
  def setup
    @output = StringIO.new
    @renderer = Konpeito::Diagnostics::DiagnosticRenderer.new(color: false, io: @output)
  end

  def test_render_basic_diagnostic
    diagnostic = Konpeito::Diagnostics::Diagnostic.new(
      severity: :error,
      code: "E001",
      message: "type mismatch"
    )

    @renderer.render(diagnostic)
    output = @output.string

    assert_includes output, "error[E001]"
    assert_includes output, "type mismatch"
  end

  def test_render_diagnostic_with_span
    source = "result = add(1, \"two\")\n"
    span = Konpeito::Diagnostics::SourceSpan.new(
      file_path: "test.rb",
      start_line: 1,
      start_column: 9,
      end_line: 1,
      end_column: 22,
      source: source
    )

    diagnostic = Konpeito::Diagnostics::Diagnostic.type_mismatch(
      expected: "Integer",
      found: "String",
      span: span
    )

    @renderer.render(diagnostic)
    output = @output.string

    assert_includes output, "test.rb:1:9"
    assert_includes output, "expected Integer, found String"
  end

  def test_render_diagnostic_with_notes
    diagnostic = Konpeito::Diagnostics::Diagnostic.new(
      severity: :error,
      code: "E020",
      message: "circular dependency",
      notes: ["a.rb -> b.rb -> a.rb"]
    )

    @renderer.render(diagnostic)
    output = @output.string

    assert_includes output, "note:"
    assert_includes output, "a.rb -> b.rb -> a.rb"
  end

  def test_render_diagnostic_with_suggestions
    diagnostic = Konpeito::Diagnostics::Diagnostic.new(
      severity: :error,
      code: "E004",
      message: "undefined variable `foo`",
      suggestions: ["did you mean `food`?"]
    )

    @renderer.render(diagnostic)
    output = @output.string

    assert_includes output, "help:"
    assert_includes output, "did you mean `food`?"
  end

  def test_render_multiple_diagnostics
    diagnostics = [
      Konpeito::Diagnostics::Diagnostic.new(severity: :error, code: "E001", message: "error 1"),
      Konpeito::Diagnostics::Diagnostic.new(severity: :error, code: "E002", message: "error 2"),
      Konpeito::Diagnostics::Diagnostic.new(severity: :warning, code: "W001", message: "warning 1")
    ]

    @renderer.render_all(diagnostics)
    output = @output.string

    assert_includes output, "E001"
    assert_includes output, "E002"
    assert_includes output, "W001"
    assert_includes output, "2 error(s)"
    assert_includes output, "1 warning(s)"
  end
end

class DiagnosticCollectorTest < Minitest::Test
  def test_collect_diagnostics
    collector = Konpeito::Diagnostics::Collector.new

    collector.add(Konpeito::Diagnostics::Diagnostic.new(
      severity: :error,
      code: "E001",
      message: "test error"
    ))

    assert_equal 1, collector.diagnostics.size
    assert collector.errors?
  end

  def test_errors_only
    collector = Konpeito::Diagnostics::Collector.new

    collector.add(Konpeito::Diagnostics::Diagnostic.new(severity: :error, code: "E001", message: "error"))
    collector.add(Konpeito::Diagnostics::Diagnostic.new(severity: :warning, code: "W001", message: "warning"))

    assert_equal 2, collector.diagnostics.size
    assert_equal 1, collector.errors.size
    assert_equal 1, collector.warnings.size
  end

  def test_register_source
    collector = Konpeito::Diagnostics::Collector.new
    source = "def foo; end"

    collector.register_source("test.rb", source)
    assert_equal source, collector.source_for("test.rb")
  end

  def test_clear
    collector = Konpeito::Diagnostics::Collector.new

    collector.add(Konpeito::Diagnostics::Diagnostic.new(severity: :error, code: "E001", message: "error"))
    assert_equal 1, collector.diagnostics.size

    collector.clear
    assert_equal 0, collector.diagnostics.size
  end
end

# frozen_string_literal: true

require "test_helper"
require "stringio"
require "konpeito/lsp/server"

class LSPServerTest < Minitest::Test
  def setup
    @input = StringIO.new("")
    @output = StringIO.new
    @server = Konpeito::LSP::Server.new(input: @input, output: @output)
  end

  def test_initialize_returns_capabilities
    response = @server.handle_request({
      method: "initialize",
      id: 1,
      params: { capabilities: {} }
    })

    assert_equal "2.0", response[:jsonrpc]
    assert_equal 1, response[:id]

    result = response[:result]
    assert result[:capabilities]
    assert result[:capabilities][:hoverProvider]
    assert result[:capabilities][:textDocumentSync]

    assert_equal "konpeito-lsp", result[:serverInfo][:name]
  end

  def test_shutdown_returns_nil
    response = @server.handle_request({
      method: "shutdown",
      id: 2,
      params: {}
    })

    assert_equal 2, response[:id]
    assert_nil response[:result]
  end

  def test_document_open_publishes_diagnostics
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "x = 42\n"
        }
      }
    })

    # Check that diagnostics were published
    @output.rewind
    output = @output.read
    assert_includes output, "publishDiagnostics"
  end

  def test_hover_returns_type_for_variable
    # Open document
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "x = 42\n"
        }
      }
    })

    # Request hover
    response = @server.handle_request({
      method: "textDocument/hover",
      id: 3,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 0, character: 0 }
      }
    })

    assert response[:result]
    contents = response[:result][:contents][:value]
    assert_includes contents, "Integer"
  end

  def test_hover_returns_function_type
    # Open document with function
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "def add(a, b)\n  a + b\nend\n"
        }
      }
    })

    # Request hover on function name
    response = @server.handle_request({
      method: "textDocument/hover",
      id: 4,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 0, character: 4 }  # on "add"
      }
    })

    assert response[:result]
    contents = response[:result][:contents][:value]
    assert_includes contents, "def add"
    assert_includes contents, "->"
  end

  def test_hover_returns_nil_for_unknown_document
    response = @server.handle_request({
      method: "textDocument/hover",
      id: 5,
      params: {
        textDocument: { uri: "file:///unknown.rb" },
        position: { line: 0, character: 0 }
      }
    })

    assert_nil response[:result]
  end

  def test_completion_returns_methods_for_integer
    # Open document with Integer variable
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "x = 42\ny = x.\n"
        }
      }
    })

    # Request completion after "x."
    response = @server.handle_request({
      method: "textDocument/completion",
      id: 6,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 1, character: 6 }  # After "x."
      }
    })

    result = response[:result]
    assert result[:items]
    assert result[:items].any? { |item| item[:label] == "to_s" }
    assert result[:items].any? { |item| item[:label] == "abs" }
  end

  def test_completion_returns_scope_items
    # Open document with variables
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "def foo; end\nx = 42\n"
        }
      }
    })

    # Request completion (not after ".")
    response = @server.handle_request({
      method: "textDocument/completion",
      id: 7,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 2, character: 0 }
      }
    })

    result = response[:result]
    assert result[:items]
    labels = result[:items].map { |i| i[:label] }
    assert_includes labels, "foo"
    assert_includes labels, "x"
  end

  def test_definition_finds_method
    # Open document with method definition and call
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "def add(a, b)\n  a + b\nend\ny = add(1, 2)\n"
        }
      }
    })

    # Request definition on "add" call
    response = @server.handle_request({
      method: "textDocument/definition",
      id: 8,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 3, character: 4 }  # On "add"
      }
    })

    result = response[:result]
    assert result
    assert_equal 0, result[:range][:start][:line]  # Line 1 (0-indexed)
  end

  def test_definition_finds_variable
    # Open document with variable assignment and use
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "x = 42\ny = x + 1\n"
        }
      }
    })

    # Request definition on "x" reference
    response = @server.handle_request({
      method: "textDocument/definition",
      id: 9,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 1, character: 4 }  # On "x"
      }
    })

    result = response[:result]
    assert result
    assert_equal 0, result[:range][:start][:line]  # Line 1 (0-indexed)
  end

  def test_document_close_clears_diagnostics
    # Open document
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "x = 42\n"
        }
      }
    })

    @output.truncate(0)
    @output.rewind

    # Close document
    @server.handle_request({
      method: "textDocument/didClose",
      params: {
        textDocument: { uri: "file:///test.rb" }
      }
    })

    # Check that empty diagnostics were published
    @output.rewind
    output = @output.read
    assert_includes output, "publishDiagnostics"
    assert_includes output, '"diagnostics":[]'
  end

  def test_references_finds_method_calls
    # Open document with method definition and multiple calls
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "def add(a, b)\n  a + b\nend\nx = add(1, 2)\ny = add(3, 4)\n"
        }
      }
    })

    # Request references on "add" definition
    response = @server.handle_request({
      method: "textDocument/references",
      id: 10,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 0, character: 4 },  # On "add" in def
        context: { includeDeclaration: true }
      }
    })

    result = response[:result]
    assert result
    assert_equal 3, result.size  # Definition + 2 calls
  end

  def test_references_finds_variable_usages
    # Open document with variable assignment and multiple uses
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "x = 42\ny = x + 1\nz = x * 2\n"
        }
      }
    })

    # Request references on "x" assignment
    response = @server.handle_request({
      method: "textDocument/references",
      id: 11,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 0, character: 0 },  # On "x" assignment
        context: { includeDeclaration: true }
      }
    })

    result = response[:result]
    assert result
    assert_equal 3, result.size  # Assignment + 2 reads
  end

  def test_references_excludes_declaration
    # Open document
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "def foo\n  1\nend\nfoo()\nfoo()\n"
        }
      }
    })

    # Request references excluding declaration
    response = @server.handle_request({
      method: "textDocument/references",
      id: 12,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 0, character: 4 },  # On "foo" in def
        context: { includeDeclaration: false }
      }
    })

    result = response[:result]
    assert result
    assert_equal 2, result.size  # Only the 2 calls, not the definition
  end

  def test_rename_method
    # Open document with method and calls
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "def add(a, b)\n  a + b\nend\nx = add(1, 2)\n"
        }
      }
    })

    # Request rename on "add" definition
    response = @server.handle_request({
      method: "textDocument/rename",
      id: 13,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 0, character: 4 },  # On "add" in def
        newName: "sum"
      }
    })

    result = response[:result]
    assert result
    assert result[:changes]
    edits = result[:changes]["file:///test.rb"]
    assert_equal 2, edits.size  # Definition + 1 call
    edits.each { |edit| assert_equal "sum", edit[:newText] }
  end

  def test_rename_variable
    # Open document with variable
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "x = 42\ny = x + 1\nz = x * 2\n"
        }
      }
    })

    # Request rename on "x"
    response = @server.handle_request({
      method: "textDocument/rename",
      id: 14,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 0, character: 0 },  # On "x" assignment
        newName: "value"
      }
    })

    result = response[:result]
    assert result
    edits = result[:changes]["file:///test.rb"]
    assert_equal 3, edits.size  # Assignment + 2 reads
    edits.each { |edit| assert_equal "value", edit[:newText] }
  end

  def test_prepare_rename
    # Open document
    @server.handle_request({
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file:///test.rb",
          languageId: "ruby",
          version: 1,
          text: "def hello\n  1\nend\n"
        }
      }
    })

    # Request prepare rename on "hello"
    response = @server.handle_request({
      method: "textDocument/prepareRename",
      id: 15,
      params: {
        textDocument: { uri: "file:///test.rb" },
        position: { line: 0, character: 4 }  # On "hello"
      }
    })

    result = response[:result]
    assert result
    assert_equal "hello", result[:placeholder]
    assert result[:range]
  end
end

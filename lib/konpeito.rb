# frozen_string_literal: true

require_relative "konpeito/version"

module Konpeito
  class Error < StandardError; end
  class ParseError < Error; end
  class TypeError < Error; end
  class CodegenError < Error; end

  class DependencyError < Error
    attr_reader :from_file, :line, :cycle, :missing_file

    def initialize(message, from_file: nil, line: nil, cycle: nil, missing_file: nil)
      @from_file = from_file
      @line = line
      @cycle = cycle  # Array of file names in the cycle
      @missing_file = missing_file
      super(message)
    end
  end

  module Diagnostics
    autoload :SourceSpan, "konpeito/diagnostics/diagnostic"
    autoload :Label, "konpeito/diagnostics/diagnostic"
    autoload :Diagnostic, "konpeito/diagnostics/diagnostic"
    autoload :DiagnosticRenderer, "konpeito/diagnostics/renderer"
    autoload :Collector, "konpeito/diagnostics/collector"
  end

  autoload :Platform, "konpeito/platform"
  autoload :CLI, "konpeito/cli"
  autoload :LegacyCLI, "konpeito/cli"
  autoload :Compiler, "konpeito/compiler"
  autoload :DependencyResolver, "konpeito/dependency_resolver"

  # Commands module for CLI subcommands
  module Commands
    autoload :Config, "konpeito/cli/config"
    autoload :BaseCommand, "konpeito/cli/base_command"
    autoload :BuildCommand, "konpeito/cli/build_command"
    autoload :CheckCommand, "konpeito/cli/check_command"
    autoload :LspCommand, "konpeito/cli/lsp_command"
    autoload :InitCommand, "konpeito/cli/init_command"
    autoload :FmtCommand, "konpeito/cli/fmt_command"
    autoload :TestCommand, "konpeito/cli/test_command"
    autoload :WatchCommand, "konpeito/cli/watch_command"
  end

  module Parser
    autoload :PrismAdapter, "konpeito/parser/prism_adapter"
  end

  module TypeChecker
    # Types must be loaded first as other modules depend on it
    require_relative "konpeito/type_checker/types"

    autoload :Checker, "konpeito/type_checker/checker"
    autoload :Inferrer, "konpeito/type_checker/inferrer"
    autoload :HMInferrer, "konpeito/type_checker/hm_inferrer"
    autoload :RBSLoader, "konpeito/type_checker/rbs_loader"
    autoload :TypeVar, "konpeito/type_checker/unification"
    autoload :FunctionType, "konpeito/type_checker/unification"
    autoload :Unifier, "konpeito/type_checker/unification"
    autoload :TypeScheme, "konpeito/type_checker/unification"
    autoload :UnificationError, "konpeito/type_checker/unification"
  end

  module AST
    autoload :TypedNode, "konpeito/ast/typed_ast"
    autoload :TypedASTBuilder, "konpeito/ast/typed_ast"
    autoload :Visitor, "konpeito/ast/visitor"
  end

  module HIR
    autoload :Builder, "konpeito/hir/builder"
    # Load nodes directly since they define classes in HIR namespace
    require_relative "konpeito/hir/nodes"
  end

  module Codegen
    autoload :LLVMGenerator, "konpeito/codegen/llvm_generator"
    autoload :CRubyBackend, "konpeito/codegen/cruby_backend"
    autoload :Monomorphizer, "konpeito/codegen/monomorphizer"
    autoload :Inliner, "konpeito/codegen/inliner"
    autoload :LoopOptimizer, "konpeito/codegen/loop_optimizer"
  end

  module LSP
    autoload :Server, "konpeito/lsp/server"
    autoload :Transport, "konpeito/lsp/transport"
    autoload :DocumentManager, "konpeito/lsp/document_manager"
  end

  module RBSInline
    autoload :Preprocessor, "konpeito/rbs_inline/preprocessor"
  end

  # Convenience method
  def self.compile(source_file, output_file: nil, format: :cruby_ext, verbose: false, optimize: true)
    Compiler.new(
      source_file: source_file,
      output_file: output_file,
      format: format,
      verbose: verbose,
      optimize: optimize
    ).compile
  end
end

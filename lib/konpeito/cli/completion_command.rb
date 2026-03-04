# frozen_string_literal: true

module Konpeito
  module Commands
    # Completion command - generates shell completion scripts
    class CompletionCommand < BaseCommand
      def self.command_name
        "completion"
      end

      def self.description
        "Generate shell completion scripts (bash, zsh, fish)"
      end

      def run
        parse_options!

        shell = args.first
        unless shell
          error("No shell specified. Usage: konpeito completion <bash|zsh|fish>")
        end

        case shell.downcase
        when "bash"
          puts bash_completion
        when "zsh"
          puts zsh_completion
        when "fish"
          puts fish_completion
        else
          error("Unsupported shell: #{shell}. Supported: bash, zsh, fish")
        end
      end

      protected

      def banner
        <<~BANNER.chomp
          Usage: konpeito completion <shell>

          Generate shell completion scripts.

          Supported shells: bash, zsh, fish

          Examples:
            eval "$(konpeito completion bash)"     # Add to .bashrc
            eval "$(konpeito completion zsh)"      # Add to .zshrc
            konpeito completion fish | source      # Add to config.fish
        BANNER
      end

      private

      SUBCOMMANDS = %w[build run check init test fmt watch lsp deps doctor completion].freeze

      BUILD_OPTIONS = %w[
        -o --output -f --format -g --debug -p --profile -v --verbose
        -I --require-path --rbs --incremental --clean-cache --inline
        --target --run --emit-ir --classpath --lib --stats -q --quiet
        --no-color -h --help
      ].freeze

      TARGET_VALUES = %w[native jvm].freeze

      def bash_completion
        <<~'BASH'
          _konpeito() {
              local cur prev commands
              COMPREPLY=()
              cur="${COMP_WORDS[COMP_CWORD]}"
              prev="${COMP_WORDS[COMP_CWORD-1]}"
              commands="build run check init test fmt watch lsp deps doctor completion"

              # Complete subcommand
              if [[ ${COMP_CWORD} -eq 1 ]]; then
                  COMPREPLY=( $(compgen -W "${commands} --help --version" -- "${cur}") )
                  return 0
              fi

              local subcmd="${COMP_WORDS[1]}"

              # Complete --target values
              if [[ "${prev}" == "--target" ]]; then
                  COMPREPLY=( $(compgen -W "native jvm" -- "${cur}") )
                  return 0
              fi

              # Complete shell names for completion command
              if [[ "${subcmd}" == "completion" && ${COMP_CWORD} -eq 2 ]]; then
                  COMPREPLY=( $(compgen -W "bash zsh fish" -- "${cur}") )
                  return 0
              fi

              # Complete options per subcommand
              case "${subcmd}" in
                  build)
                      if [[ "${cur}" == -* ]]; then
                          COMPREPLY=( $(compgen -W "-o --output -f --format -g --debug -p --profile -v --verbose -I --require-path --rbs --incremental --clean-cache --inline --target --run --emit-ir --classpath --lib --stats -q --quiet --no-color -h --help" -- "${cur}") )
                      else
                          COMPREPLY=( $(compgen -f -X '!*.rb' -- "${cur}") )
                      fi
                      ;;
                  run)
                      if [[ "${cur}" == -* ]]; then
                          COMPREPLY=( $(compgen -W "--target --classpath --rbs -I --require-path --inline -v --verbose --no-color -h --help" -- "${cur}") )
                      else
                          COMPREPLY=( $(compgen -f -X '!*.rb' -- "${cur}") )
                      fi
                      ;;
                  check)
                      if [[ "${cur}" == -* ]]; then
                          COMPREPLY=( $(compgen -W "-v --verbose --rbs -I --require-path --no-color -h --help" -- "${cur}") )
                      else
                          COMPREPLY=( $(compgen -f -X '!*.rb' -- "${cur}") )
                      fi
                      ;;
                  init)
                      COMPREPLY=( $(compgen -W "-h --help" -- "${cur}") )
                      ;;
                  test|fmt|watch|lsp|deps|doctor)
                      COMPREPLY=( $(compgen -W "-v --verbose --no-color -h --help" -- "${cur}") )
                      ;;
              esac
              return 0
          }
          complete -F _konpeito konpeito
        BASH
      end

      def zsh_completion
        <<~'ZSH'
          #compdef konpeito

          _konpeito() {
              local -a commands
              commands=(
                  'build:Compile Ruby source to native code'
                  'run:Build and run a Konpeito program'
                  'check:Type check only (no code generation)'
                  'init:Initialize a new Konpeito project'
                  'test:Run tests'
                  'fmt:Format source files'
                  'watch:Watch files and recompile on changes'
                  'lsp:Start Language Server Protocol server'
                  'deps:Analyze dependencies'
                  'doctor:Check environment setup'
                  'completion:Generate shell completion scripts'
              )

              if (( CURRENT == 2 )); then
                  _describe 'command' commands
                  return
              fi

              case "${words[2]}" in
                  build)
                      _arguments \
                          '-o[Output file name]:file:_files' \
                          '--output[Output file name]:file:_files' \
                          '-f[Output format]:format:(cruby_ext standalone)' \
                          '--format[Output format]:format:(cruby_ext standalone)' \
                          '-g[Generate debug info (DWARF)]' \
                          '--debug[Generate debug info (DWARF)]' \
                          '-p[Enable profiling]' \
                          '--profile[Enable profiling]' \
                          '-v[Verbose output]' \
                          '--verbose[Verbose output]' \
                          '-I[Add require search path]:path:_directories' \
                          '--require-path[Add require search path]:path:_directories' \
                          '--rbs[RBS type definition file]:file:_files -g "*.rbs"' \
                          '--incremental[Enable incremental compilation]' \
                          '--clean-cache[Clear compilation cache]' \
                          '--inline[Use inline RBS annotations]' \
                          '--target[Target platform]:target:(native jvm)' \
                          '--run[Run after building]' \
                          '--emit-ir[Emit intermediate representation]' \
                          '--classpath[JVM classpath]:path:_files' \
                          '--lib[Build as library JAR]' \
                          '--stats[Show optimization statistics]' \
                          '-q[Suppress non-error output]' \
                          '--quiet[Suppress non-error output]' \
                          '--no-color[Disable colored output]' \
                          '-h[Show help]' \
                          '--help[Show help]' \
                          '*:source file:_files -g "*.rb"'
                      ;;
                  run)
                      _arguments \
                          '--target[Target platform]:target:(native jvm)' \
                          '--classpath[JVM classpath]:path:_files' \
                          '--rbs[RBS type definition file]:file:_files -g "*.rbs"' \
                          '-I[Add require search path]:path:_directories' \
                          '--require-path[Add require search path]:path:_directories' \
                          '--inline[Use inline RBS annotations]' \
                          '-v[Verbose output]' \
                          '--verbose[Verbose output]' \
                          '--no-color[Disable colored output]' \
                          '-h[Show help]' \
                          '--help[Show help]' \
                          '*:source file:_files -g "*.rb"'
                      ;;
                  check)
                      _arguments \
                          '-v[Verbose output]' \
                          '--verbose[Verbose output]' \
                          '--rbs[RBS type definition file]:file:_files -g "*.rbs"' \
                          '-I[Add require search path]:path:_directories' \
                          '--require-path[Add require search path]:path:_directories' \
                          '--no-color[Disable colored output]' \
                          '-h[Show help]' \
                          '--help[Show help]' \
                          '*:source file:_files -g "*.rb"'
                      ;;
                  completion)
                      _arguments \
                          '1:shell:(bash zsh fish)'
                      ;;
                  *)
                      _arguments \
                          '-v[Verbose output]' \
                          '--verbose[Verbose output]' \
                          '--no-color[Disable colored output]' \
                          '-h[Show help]' \
                          '--help[Show help]'
                      ;;
              esac
          }

          _konpeito "$@"
        ZSH
      end

      def fish_completion
        <<~'FISH'
          # konpeito completions for fish shell

          # Disable file completions by default
          complete -c konpeito -f

          # Subcommands
          complete -c konpeito -n '__fish_use_subcommand' -a 'build' -d 'Compile Ruby source to native code'
          complete -c konpeito -n '__fish_use_subcommand' -a 'run' -d 'Build and run a Konpeito program'
          complete -c konpeito -n '__fish_use_subcommand' -a 'check' -d 'Type check only'
          complete -c konpeito -n '__fish_use_subcommand' -a 'init' -d 'Initialize a new project'
          complete -c konpeito -n '__fish_use_subcommand' -a 'test' -d 'Run tests'
          complete -c konpeito -n '__fish_use_subcommand' -a 'fmt' -d 'Format source files'
          complete -c konpeito -n '__fish_use_subcommand' -a 'watch' -d 'Watch and recompile'
          complete -c konpeito -n '__fish_use_subcommand' -a 'lsp' -d 'Start LSP server'
          complete -c konpeito -n '__fish_use_subcommand' -a 'deps' -d 'Analyze dependencies'
          complete -c konpeito -n '__fish_use_subcommand' -a 'doctor' -d 'Check environment'
          complete -c konpeito -n '__fish_use_subcommand' -a 'completion' -d 'Generate shell completions'

          # Global options
          complete -c konpeito -n '__fish_use_subcommand' -l help -s h -d 'Show help'
          complete -c konpeito -n '__fish_use_subcommand' -l version -s V -d 'Show version'

          # build options
          complete -c konpeito -n '__fish_seen_subcommand_from build' -s o -l output -r -d 'Output file name'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -s f -l format -r -a 'cruby_ext standalone' -d 'Output format'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -s g -l debug -d 'Generate debug info'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -s p -l profile -d 'Enable profiling'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -s v -l verbose -d 'Verbose output'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -s I -l require-path -r -d 'Add require search path'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l rbs -r -d 'RBS type definition file'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l incremental -d 'Incremental compilation'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l clean-cache -d 'Clear compilation cache'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l inline -d 'Use inline RBS annotations'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l target -r -a 'native jvm' -d 'Target platform'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l run -d 'Run after building'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l emit-ir -d 'Emit intermediate representation'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l classpath -r -d 'JVM classpath'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l lib -d 'Build as library JAR'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l stats -d 'Show optimization statistics'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -s q -l quiet -d 'Suppress non-error output'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -l no-color -d 'Disable colored output'
          complete -c konpeito -n '__fish_seen_subcommand_from build' -F -d 'Ruby source file'

          # run options
          complete -c konpeito -n '__fish_seen_subcommand_from run' -l target -r -a 'native jvm' -d 'Target platform'
          complete -c konpeito -n '__fish_seen_subcommand_from run' -l classpath -r -d 'JVM classpath'
          complete -c konpeito -n '__fish_seen_subcommand_from run' -l rbs -r -d 'RBS type definition file'
          complete -c konpeito -n '__fish_seen_subcommand_from run' -s I -l require-path -r -d 'Add require search path'
          complete -c konpeito -n '__fish_seen_subcommand_from run' -s v -l verbose -d 'Verbose output'
          complete -c konpeito -n '__fish_seen_subcommand_from run' -l no-color -d 'Disable colored output'
          complete -c konpeito -n '__fish_seen_subcommand_from run' -F -d 'Ruby source file'

          # check options
          complete -c konpeito -n '__fish_seen_subcommand_from check' -s v -l verbose -d 'Verbose output'
          complete -c konpeito -n '__fish_seen_subcommand_from check' -l rbs -r -d 'RBS type definition file'
          complete -c konpeito -n '__fish_seen_subcommand_from check' -s I -l require-path -r -d 'Add require search path'
          complete -c konpeito -n '__fish_seen_subcommand_from check' -l no-color -d 'Disable colored output'
          complete -c konpeito -n '__fish_seen_subcommand_from check' -F -d 'Ruby source file'

          # completion options
          complete -c konpeito -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish' -d 'Shell type'
        FISH
      end
    end
  end
end

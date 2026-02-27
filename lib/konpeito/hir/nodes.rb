# frozen_string_literal: true

module Konpeito
  module HIR
    # Source location information for debug info
    class SourceLocation
      attr_reader :line, :column, :file

      def initialize(line: nil, column: nil, file: nil)
        @line = line
        @column = column
        @file = file
      end

      def self.from_prism(prism_location, file: nil)
        return nil unless prism_location

        new(
          line: prism_location.start_line,
          column: prism_location.start_column,
          file: file
        )
      end
    end

    # Base class for all HIR nodes
    class Node
      attr_reader :type  # TypeChecker::Types::Type
      attr_accessor :location  # SourceLocation for debug info

      def initialize(type: TypeChecker::Types::UNTYPED, location: nil)
        @type = type
        @location = location
      end
    end

    # Program is the top-level container
    class Program < Node
      attr_reader :functions, :classes, :modules
      attr_accessor :toplevel_constants  # Array of [name, literal_node] for top-level constants

      def initialize(functions: [], classes: [], modules: [])
        super(type: TypeChecker::Types::NIL)
        @functions = functions
        @classes = classes
        @modules = modules
        @toplevel_constants = []
      end
    end

    # Class definition
    class ClassDef < Node
      attr_reader :name, :superclass, :instance_vars
      attr_accessor :method_names  # Names of methods defined in this class
      attr_accessor :included_modules  # Module names included by this class
      attr_accessor :extended_modules   # Module names extended by this class
      attr_accessor :prepended_modules  # Module names prepended by this class
      attr_accessor :private_methods    # Set of private method names
      attr_accessor :protected_methods  # Set of protected method names
      attr_accessor :aliases            # Array of [new_name, old_name] pairs
      attr_accessor :reopened           # true if this is reopening an existing class
      attr_accessor :singleton_methods  # Names of class-level methods (def self.xxx or class << self)
      attr_accessor :instance_var_types # HM-inferred ivar types: { "name" => :Integer, "age" => :String, ... }
      attr_accessor :body_constants     # Array of [name, value_node] for constants defined in class body
      attr_accessor :body_class_vars    # Array of [name, value_node] for class variables initialized in class body

      def initialize(name:, superclass: nil, method_names: [], instance_vars: [], included_modules: [], extended_modules: [], prepended_modules: [])
        super(type: TypeChecker::Types::NIL)
        @name = name
        @superclass = superclass
        @method_names = method_names
        @instance_vars = instance_vars
        @included_modules = included_modules
        @extended_modules = extended_modules
        @prepended_modules = prepended_modules
        @private_methods = Set.new
        @protected_methods = Set.new
        @aliases = []
        @reopened = false
        @singleton_methods = []
        @instance_var_types = {}
        @body_constants = []
        @body_class_vars = []
      end
    end

    # Module definition
    class ModuleDef < Node
      attr_reader :name, :methods, :singleton_methods, :constants

      def initialize(name:, methods: [], singleton_methods: [], constants: {})
        super(type: TypeChecker::Types::NIL)
        @name = name
        @methods = methods
        @singleton_methods = singleton_methods
        @constants = constants  # Hash of name -> value
      end
    end

    # Function/method definition
    class Function < Node
      attr_reader :name, :params, :body, :return_type
      attr_accessor :is_instance_method
      attr_accessor :owner_class  # Class name this method belongs to (nil for top-level)
      attr_accessor :owner_module  # Module name this method belongs to (nil for top-level or class methods)

      def initialize(name:, params: [], body: [], return_type: TypeChecker::Types::UNTYPED, is_instance_method: true, owner_class: nil, owner_module: nil, location: nil)
        super(type: TypeChecker::Types::SYMBOL, location: location)
        @name = name
        @params = params
        @body = body  # Array of BasicBlock
        @return_type = return_type
        @is_instance_method = is_instance_method
        @owner_class = owner_class
        @owner_module = owner_module
      end

      def entry_block
        body.first
      end

      def class_method?
        !is_instance_method && owner_class
      end
    end

    # Function parameter
    class Param < Node
      attr_reader :name, :default_value, :rest, :keyword, :keyword_rest, :block

      def initialize(name:, type: TypeChecker::Types::UNTYPED, default_value: nil, rest: false, keyword: false, keyword_rest: false, block: false)
        super(type: type)
        @name = name
        @default_value = default_value
        @rest = rest
        @keyword = keyword
        @keyword_rest = keyword_rest  # **kwargs
        @block = block
      end
    end

    # Basic block (sequence of instructions ending in a terminator)
    class BasicBlock
      attr_reader :label, :instructions, :terminator

      def initialize(label:)
        @label = label
        @instructions = []
        @terminator = nil
      end

      def add_instruction(inst)
        @instructions << inst
      end

      def set_terminator(term)
        @terminator = term
      end
    end

    # Base class for instructions
    class Instruction < Node
      attr_reader :result_var  # Variable to store result (nil if void)

      def initialize(type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type)
        @result_var = result_var
      end
    end

    # Terminators (end a basic block)
    class Terminator < Node; end

    class Return < Terminator
      attr_reader :value

      def initialize(value: nil)
        super(type: TypeChecker::Types::BOTTOM)
        @value = value
      end
    end

    class Branch < Terminator
      attr_reader :condition, :then_block, :else_block

      def initialize(condition:, then_block:, else_block:)
        super(type: TypeChecker::Types::BOTTOM)
        @condition = condition
        @then_block = then_block
        @else_block = else_block
      end
    end

    class Jump < Terminator
      attr_reader :target

      def initialize(target:)
        super(type: TypeChecker::Types::BOTTOM)
        @target = target
      end
    end

    # Include statement for including modules into classes
    class IncludeStatement < Instruction
      attr_reader :module_name

      def initialize(module_name:)
        super(type: TypeChecker::Types::NIL)
        @module_name = module_name
      end
    end

    # Variable operations
    class LocalVar < Node
      attr_reader :name

      def initialize(name:, type: TypeChecker::Types::UNTYPED)
        super(type: type)
        @name = name
      end
    end

    class LoadLocal < Instruction
      attr_reader :var

      def initialize(var:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @var = var
      end
    end

    class StoreLocal < Instruction
      attr_reader :var, :value

      def initialize(var:, value:, type: TypeChecker::Types::UNTYPED)
        super(type: type)
        @var = var
        @value = value
      end
    end

    class LoadInstanceVar < Instruction
      attr_reader :name

      def initialize(name:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @name = name
      end
    end

    class StoreInstanceVar < Instruction
      attr_reader :name, :value

      def initialize(name:, value:, type: TypeChecker::Types::UNTYPED)
        super(type: type)
        @name = name
        @value = value
      end
    end

    # Class variable operations (@@var)
    class LoadClassVar < Instruction
      attr_reader :name

      def initialize(name:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @name = name  # e.g., "@@counter"
      end
    end

    class StoreClassVar < Instruction
      attr_reader :name, :value

      def initialize(name:, value:, type: TypeChecker::Types::UNTYPED)
        super(type: type)
        @name = name  # e.g., "@@counter"
        @value = value
      end
    end

    # Constant assignment: CONSTANT = value
    class StoreConstant < Instruction
      attr_reader :name, :value, :scope

      def initialize(name:, value:, scope: nil, type: TypeChecker::Types::UNTYPED)
        super(type: type)
        @name = name        # e.g., "VERSION"
        @value = value      # The value HIR node
        @scope = scope      # nil for top-level, module/class name otherwise
      end
    end

    # Literals
    class Literal < Instruction
      attr_reader :value

      def initialize(value:, type:, result_var: nil)
        super(type: type, result_var: result_var)
        @value = value
      end
    end

    class IntegerLit < Literal
      def initialize(value:, result_var: nil)
        super(value: value, type: TypeChecker::Types::INTEGER, result_var: result_var)
      end
    end

    class FloatLit < Literal
      def initialize(value:, result_var: nil)
        super(value: value, type: TypeChecker::Types::FLOAT, result_var: result_var)
      end
    end

    class StringLit < Literal
      def initialize(value:, result_var: nil)
        super(value: value, type: TypeChecker::Types::STRING, result_var: result_var)
      end
    end

    # String concatenation chain optimization: a + b + c + d
    # Instead of creating intermediate strings with rb_str_plus,
    # we use rb_str_dup + rb_str_concat for efficiency
    class StringConcat < Instruction
      attr_reader :parts, :result_var

      def initialize(parts:, result_var: nil)
        @parts = parts  # Array of HIR instructions representing string parts
        @result_var = result_var
      end

      def type
        TypeChecker::Types::STRING
      end
    end

    class SymbolLit < Literal
      def initialize(value:, result_var: nil)
        super(value: value, type: TypeChecker::Types::SYMBOL, result_var: result_var)
      end
    end

    class RegexpLit < Instruction
      attr_reader :pattern, :options, :result_var

      def initialize(pattern:, options: 0, result_var: nil)
        @pattern = pattern
        @options = options  # Integer: Regexp::IGNORECASE | Regexp::EXTENDED | Regexp::MULTILINE
        @result_var = result_var
      end

      def type
        TypeChecker::Types::REGEXP
      end
    end

    class NilLit < Literal
      def initialize(result_var: nil)
        super(value: nil, type: TypeChecker::Types::NIL, result_var: result_var)
      end
    end

    class BoolLit < Literal
      def initialize(value:, result_var: nil)
        type = value ? TypeChecker::Types::TRUE_CLASS : TypeChecker::Types::FALSE_CLASS
        super(value: value, type: type, result_var: result_var)
      end
    end

    # Array literal
    class ArrayLit < Instruction
      attr_reader :elements

      def initialize(elements:, element_type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: TypeChecker::Types.array(element_type), result_var: result_var)
        @elements = elements
      end
    end

    # Hash literal
    class HashLit < Instruction
      attr_reader :pairs  # Array of [key, value] pairs

      def initialize(pairs:, key_type: TypeChecker::Types::UNTYPED, value_type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: TypeChecker::Types.hash_type(key_type, value_type), result_var: result_var)
        @pairs = pairs
      end
    end

    # Method call
    class Call < Instruction
      attr_reader :receiver, :method_name, :args, :block, :keyword_args, :safe_navigation

      def initialize(receiver:, method_name:, args: [], block: nil, keyword_args: {}, type: TypeChecker::Types::UNTYPED, result_var: nil, safe_navigation: false)
        super(type: type, result_var: result_var)
        @receiver = receiver
        @method_name = method_name
        @args = args
        @block = block
        @keyword_args = keyword_args  # Hash of { keyword_name => HIR instruction }
        @safe_navigation = safe_navigation
      end

      def has_keyword_args?
        !@keyword_args.empty?
      end
    end

    # Self reference
    class SelfRef < Instruction
      def initialize(type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
      end
    end

    # Range literal
    class RangeLit < Instruction
      attr_reader :left, :right, :exclusive

      def initialize(left:, right:, exclusive:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @left = left
        @right = right
        @exclusive = exclusive
      end
    end

    # Global variable read
    class LoadGlobalVar < Instruction
      attr_reader :name

      def initialize(name:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @name = name
      end
    end

    # Global variable write
    class StoreGlobalVar < Instruction
      attr_reader :name, :value

      def initialize(name:, value:, type: TypeChecker::Types::UNTYPED)
        super(type: type)
        @name = name
        @value = value
      end
    end

    # Splat argument at call site
    class SplatArg < Instruction
      attr_reader :expression

      def initialize(expression:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @expression = expression
      end
    end

    # defined? operator
    class DefinedCheck < Instruction
      attr_reader :check_type, :name

      def initialize(check_type:, name:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @check_type = check_type  # :local_variable, :constant, :method, :expression
        @name = name
      end
    end

    # Super method call
    class SuperCall < Instruction
      attr_reader :args, :forward_args

      def initialize(args: [], forward_args: false, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @args = args
        @forward_args = forward_args
      end
    end

    # Multi-write array element extraction
    class MultiWriteExtract < Instruction
      attr_reader :array, :index

      def initialize(array:, index:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @array = array
        @index = index
      end
    end

    # Multi-write splat extraction: a, *rest = arr → rest = arr[start..end]
    class MultiWriteSplat < Instruction
      attr_reader :array, :start_index, :end_offset

      def initialize(array:, start_index:, end_offset:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @array = array
        @start_index = start_index     # Index to start collecting from
        @end_offset = end_offset       # Number of elements to exclude from end (for trailing targets)
      end
    end

    # Constant lookup
    class ConstantLookup < Instruction
      attr_reader :name, :scope

      def initialize(name:, scope: nil, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @name = name
        @scope = scope
      end
    end

    # Captured variable from outer scope (for closures)
    class Capture
      attr_reader :name, :type

      def initialize(name:, type:)
        @name = name
        @type = type
      end
    end

    # Block/Lambda definition
    class BlockDef < Node
      attr_reader :params, :body, :captures, :is_lambda

      def initialize(params: [], body: [], captures: [], is_lambda: false)
        super(type: TypeChecker::Types::ClassInstance.new(:Proc))
        @params = params
        @body = body  # Array of BasicBlock
        @captures = captures  # Array of Capture objects
        @is_lambda = is_lambda
      end
    end

    # Create a Proc/Lambda object from a block definition
    class ProcNew < Instruction
      attr_reader :block_def

      def initialize(block_def:, result_var: nil)
        super(type: TypeChecker::Types::ClassInstance.new(:Proc), result_var: result_var)
        @block_def = block_def
      end
    end

    # Call a Proc/Lambda object
    class ProcCall < Instruction
      attr_reader :proc_value, :args

      def initialize(proc_value:, args: [], type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @proc_value = proc_value  # HIR instruction that evaluates to the Proc
        @args = args  # Array of HIR instructions for arguments
      end
    end

    # ========================================
    # Fiber operations
    # Cooperative concurrency primitives
    # ========================================

    # Create a new Fiber from a block definition
    # Fiber.new { |arg| ... }
    class FiberNew < Instruction
      attr_reader :block_def

      def initialize(block_def:, result_var: nil)
        super(type: TypeChecker::Types::FIBER, result_var: result_var)
        @block_def = block_def  # BlockDef with fiber body
      end
    end

    # Resume a fiber with optional arguments
    # fiber.resume(arg1, arg2)
    class FiberResume < Instruction
      attr_reader :fiber, :args

      def initialize(fiber:, args: [], type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @fiber = fiber  # HIR instruction evaluating to Fiber
        @args = args    # Array of HIR instructions for arguments
      end
    end

    # Yield from within a fiber
    # Fiber.yield(value)
    class FiberYield < Instruction
      attr_reader :args

      def initialize(args: [], type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @args = args  # Array of HIR instructions for yield values
      end
    end

    # Check if fiber is alive
    # fiber.alive?
    class FiberAlive < Instruction
      attr_reader :fiber

      def initialize(fiber:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @fiber = fiber  # HIR instruction evaluating to Fiber
      end
    end

    # Get current fiber
    # Fiber.current
    class FiberCurrent < Instruction
      def initialize(result_var: nil)
        super(type: TypeChecker::Types::FIBER, result_var: result_var)
      end
    end

    # ========================================
    # Thread operations
    # OS-level threading with GVL
    # ========================================

    # Create a new Thread from a block definition
    # Thread.new { ... }
    class ThreadNew < Instruction
      attr_reader :block_def

      def initialize(block_def:, result_var: nil)
        super(type: TypeChecker::Types::THREAD, result_var: result_var)
        @block_def = block_def  # BlockDef with thread body
      end
    end

    # Wait for thread completion
    # thread.join or thread.join(timeout)
    class ThreadJoin < Instruction
      attr_reader :thread, :timeout

      def initialize(thread:, timeout: nil, type: TypeChecker::Types::THREAD, result_var: nil)
        super(type: type, result_var: result_var)
        @thread = thread   # HIR instruction evaluating to Thread
        @timeout = timeout # Optional timeout value
      end
    end

    # Get thread return value
    # thread.value
    class ThreadValue < Instruction
      attr_reader :thread

      def initialize(thread:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @thread = thread  # HIR instruction evaluating to Thread
      end
    end

    # Get current thread
    # Thread.current
    class ThreadCurrent < Instruction
      def initialize(result_var: nil)
        super(type: TypeChecker::Types::THREAD, result_var: result_var)
      end
    end

    # ========================================
    # Mutex operations
    # Thread synchronization primitives
    # ========================================

    # Create a new Mutex
    # Mutex.new
    class MutexNew < Instruction
      def initialize(result_var: nil)
        super(type: TypeChecker::Types::MUTEX, result_var: result_var)
      end
    end

    # Lock a mutex
    # mutex.lock
    class MutexLock < Instruction
      attr_reader :mutex

      def initialize(mutex:, result_var: nil)
        super(type: TypeChecker::Types::MUTEX, result_var: result_var)
        @mutex = mutex  # HIR instruction evaluating to Mutex
      end
    end

    # Unlock a mutex
    # mutex.unlock
    class MutexUnlock < Instruction
      attr_reader :mutex

      def initialize(mutex:, result_var: nil)
        super(type: TypeChecker::Types::MUTEX, result_var: result_var)
        @mutex = mutex  # HIR instruction evaluating to Mutex
      end
    end

    # Execute block with mutex locked
    # mutex.synchronize { ... }
    class MutexSynchronize < Instruction
      attr_reader :mutex, :block_def

      def initialize(mutex:, block_def:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @mutex = mutex        # HIR instruction evaluating to Mutex
        @block_def = block_def # BlockDef with synchronized body
      end
    end

    # ========================================
    # Queue operations
    # Thread-safe queue for producer/consumer
    # ========================================

    # Create a new Queue
    # Queue.new
    class QueueNew < Instruction
      def initialize(result_var: nil)
        super(type: TypeChecker::Types::QUEUE, result_var: result_var)
      end
    end

    # Push value to queue
    # queue.push(value) or queue << value
    class QueuePush < Instruction
      attr_reader :queue, :value

      def initialize(queue:, value:, result_var: nil)
        super(type: TypeChecker::Types::QUEUE, result_var: result_var)
        @queue = queue  # HIR instruction evaluating to Queue
        @value = value  # Value to push
      end
    end

    # Pop value from queue (blocking)
    # queue.pop or queue.pop(non_block)
    class QueuePop < Instruction
      attr_reader :queue, :non_block

      def initialize(queue:, non_block: nil, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @queue = queue        # HIR instruction evaluating to Queue
        @non_block = non_block # Optional non-blocking flag
      end
    end

    # ========================================
    # ConditionVariable operations
    # ========================================

    # Create a new ConditionVariable
    # ConditionVariable.new
    class ConditionVariableNew < Instruction
      def initialize(result_var: nil)
        super(type: TypeChecker::Types::CONDITION_VARIABLE, result_var: result_var)
      end
    end

    # Wait on condition variable (releases mutex, waits, reacquires)
    # cv.wait(mutex) or cv.wait(mutex, timeout)
    class ConditionVariableWait < Instruction
      attr_reader :cv, :mutex, :timeout

      def initialize(cv:, mutex:, timeout: nil, result_var: nil)
        super(type: TypeChecker::Types::CONDITION_VARIABLE, result_var: result_var)
        @cv = cv          # HIR instruction evaluating to ConditionVariable
        @mutex = mutex    # HIR instruction evaluating to Mutex
        @timeout = timeout # Optional timeout value
      end
    end

    # Signal one waiting thread
    # cv.signal
    class ConditionVariableSignal < Instruction
      attr_reader :cv

      def initialize(cv:, result_var: nil)
        super(type: TypeChecker::Types::CONDITION_VARIABLE, result_var: result_var)
        @cv = cv  # HIR instruction evaluating to ConditionVariable
      end
    end

    # Broadcast to all waiting threads
    # cv.broadcast
    class ConditionVariableBroadcast < Instruction
      attr_reader :cv

      def initialize(cv:, result_var: nil)
        super(type: TypeChecker::Types::CONDITION_VARIABLE, result_var: result_var)
        @cv = cv  # HIR instruction evaluating to ConditionVariable
      end
    end

    # ========================================
    # SizedQueue operations
    # ========================================

    # Create a new SizedQueue with max size
    # SizedQueue.new(max)
    class SizedQueueNew < Instruction
      attr_reader :max_size

      def initialize(max_size:, result_var: nil)
        super(type: TypeChecker::Types::SIZED_QUEUE, result_var: result_var)
        @max_size = max_size  # HIR instruction evaluating to max size
      end
    end

    # Push to sized queue (blocks if full)
    # sq.push(value) or sq << value
    class SizedQueuePush < Instruction
      attr_reader :queue, :value

      def initialize(queue:, value:, result_var: nil)
        super(type: TypeChecker::Types::SIZED_QUEUE, result_var: result_var)
        @queue = queue  # HIR instruction evaluating to SizedQueue
        @value = value  # Value to push
      end
    end

    # Pop from sized queue (blocks if empty)
    # sq.pop or sq.pop(non_block)
    class SizedQueuePop < Instruction
      attr_reader :queue, :non_block

      def initialize(queue:, non_block: nil, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @queue = queue        # HIR instruction evaluating to SizedQueue
        @non_block = non_block # Optional non-blocking flag
      end
    end

    # ========================================
    # Ractor operations
    # Ruby 4.0 Ractor with Port-based communication
    # ========================================

    # Create a new Ractor
    # Ractor.new { block } or Ractor.new(name: "worker") { block }
    class RactorNew < Instruction
      attr_reader :block_def, :args, :name

      def initialize(block_def:, args: [], name: nil, result_var: nil)
        super(type: TypeChecker::Types::RACTOR, result_var: result_var)
        @block_def = block_def
        @args = args
        @name = name  # Optional name string (HIR instruction or nil)
      end
    end

    # Send message to Ractor
    # ractor.send(msg) or ractor << msg
    class RactorSend < Instruction
      attr_reader :ractor, :value

      def initialize(ractor:, value:, result_var: nil)
        super(type: TypeChecker::Types::RACTOR, result_var: result_var)
        @ractor = ractor
        @value = value
      end
    end

    # Receive message on current Ractor
    # Ractor.receive
    class RactorReceive < Instruction
      def initialize(type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
      end
    end

    # Wait for Ractor completion
    # ractor.join
    class RactorJoin < Instruction
      attr_reader :ractor

      def initialize(ractor:, result_var: nil)
        super(type: TypeChecker::Types::RACTOR, result_var: result_var)
        @ractor = ractor
      end
    end

    # Get Ractor return value
    # ractor.value
    class RactorValue < Instruction
      attr_reader :ractor

      def initialize(ractor:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @ractor = ractor
      end
    end

    # Close Ractor
    # ractor.close
    class RactorClose < Instruction
      attr_reader :ractor

      def initialize(ractor:, result_var: nil)
        super(type: TypeChecker::Types::NIL, result_var: result_var)
        @ractor = ractor
      end
    end

    # Get current Ractor
    # Ractor.current
    class RactorCurrent < Instruction
      def initialize(result_var: nil)
        super(type: TypeChecker::Types::RACTOR, result_var: result_var)
      end
    end

    # Get main Ractor
    # Ractor.main
    class RactorMain < Instruction
      def initialize(result_var: nil)
        super(type: TypeChecker::Types::RACTOR, result_var: result_var)
      end
    end

    # Get Ractor name
    # ractor.name
    class RactorName < Instruction
      attr_reader :ractor

      def initialize(ractor:, result_var: nil)
        super(type: TypeChecker::Types::STRING, result_var: result_var)
        @ractor = ractor
      end
    end

    # Ractor-local storage get
    # Ractor[:key]
    class RactorLocalGet < Instruction
      attr_reader :key

      def initialize(key:, result_var: nil)
        super(type: TypeChecker::Types::UNTYPED, result_var: result_var)
        @key = key  # HIR instruction for key (SymbolLit or StringLit)
      end
    end

    # Ractor-local storage set
    # Ractor[:key] = value
    class RactorLocalSet < Instruction
      attr_reader :key, :value

      def initialize(key:, value:, result_var: nil)
        super(type: TypeChecker::Types::UNTYPED, result_var: result_var)
        @key = key    # HIR instruction for key
        @value = value # HIR instruction for value
      end
    end

    # Ractor.make_shareable(obj)
    class RactorMakeSharable < Instruction
      attr_reader :value

      def initialize(value:, result_var: nil)
        super(type: TypeChecker::Types::UNTYPED, result_var: result_var)
        @value = value
      end
    end

    # Ractor.shareable?(obj)
    class RactorSharable < Instruction
      attr_reader :value

      def initialize(value:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @value = value
      end
    end

    # ractor.monitor(port)
    class RactorMonitor < Instruction
      attr_reader :ractor, :port

      def initialize(ractor:, port:, result_var: nil)
        super(type: TypeChecker::Types::NIL, result_var: result_var)
        @ractor = ractor
        @port = port
      end
    end

    # ractor.unmonitor(port)
    class RactorUnmonitor < Instruction
      attr_reader :ractor, :port

      def initialize(ractor:, port:, result_var: nil)
        super(type: TypeChecker::Types::NIL, result_var: result_var)
        @ractor = ractor
        @port = port
      end
    end

    # ========================================
    # Ractor::Port operations
    # ========================================

    # Create a new Ractor::Port
    # Ractor::Port.new
    class RactorPortNew < Instruction
      def initialize(result_var: nil)
        super(type: TypeChecker::Types::RACTOR_PORT, result_var: result_var)
      end
    end

    # Send message to port
    # port.send(msg) or port << msg
    class RactorPortSend < Instruction
      attr_reader :port, :value

      def initialize(port:, value:, result_var: nil)
        super(type: TypeChecker::Types::RACTOR_PORT, result_var: result_var)
        @port = port
        @value = value
      end
    end

    # Receive message from port
    # port.receive
    class RactorPortReceive < Instruction
      attr_reader :port

      def initialize(port:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @port = port
      end
    end

    # Close port
    # port.close
    class RactorPortClose < Instruction
      attr_reader :port

      def initialize(port:, result_var: nil)
        super(type: TypeChecker::Types::NIL, result_var: result_var)
        @port = port
      end
    end

    # ========================================
    # Ractor.select
    # ========================================

    # Select from multiple ports/ractors
    # Ractor.select(*ports_or_ractors)
    class RactorSelect < Instruction
      attr_reader :sources

      def initialize(sources:, result_var: nil)
        super(type: TypeChecker::Types::UNTYPED, result_var: result_var)
        @sources = sources
      end
    end

    # Yield to block
    class Yield < Instruction
      attr_reader :args

      def initialize(args: [], type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @args = args
      end
    end

    # Exception handling
    class RaiseException < Terminator
      attr_reader :exception

      def initialize(exception:)
        super(type: TypeChecker::Types::BOTTOM)
        @exception = exception
      end
    end

    # Rescue clause: represents a single rescue handler
    # rescue TypeError, ArgumentError => e
    #   handle_error
    # end
    class RescueClause < Node
      attr_reader :exception_classes  # Array of exception class names (e.g., ["TypeError", "ArgumentError"])
      attr_reader :exception_var      # Local variable name for caught exception (e.g., "e"), nil if not specified
      attr_reader :body_blocks        # Array of BasicBlock for handler body

      def initialize(exception_classes: [], exception_var: nil, body_blocks: [])
        super(type: TypeChecker::Types::UNTYPED)
        @exception_classes = exception_classes.empty? ? ["StandardError"] : exception_classes
        @exception_var = exception_var
        @body_blocks = body_blocks
      end
    end

    class BeginRescue < Instruction
      attr_reader :try_blocks, :rescue_clauses, :else_blocks, :ensure_blocks
      attr_accessor :non_try_instruction_ids

      def initialize(try_blocks:, rescue_clauses: [], else_blocks: [], ensure_blocks: [], type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @try_blocks = try_blocks
        @rescue_clauses = rescue_clauses  # Array of RescueClause
        @else_blocks = else_blocks        # Array of BasicBlock (runs if no exception)
        @ensure_blocks = ensure_blocks    # Array of BasicBlock (always runs)
        @non_try_instruction_ids = nil    # Set of object_ids for all rescue/else/ensure instructions
      end
    end

    # Case/when statement
    # case x
    # when 1 then "one"
    # when 2, 3 then "small"
    # else "other"
    # end
    class CaseStatement < Instruction
      attr_reader :predicate      # HIR instruction for the value being matched (nil for case without predicate)
      attr_reader :when_clauses   # Array of WhenClause
      attr_reader :else_body      # Array of HIR instructions for else branch (nil if no else)
      attr_accessor :sub_instruction_ids  # Set of object_ids for when/else instructions (including sub-exprs)

      def initialize(predicate:, when_clauses: [], else_body: nil, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @predicate = predicate
        @when_clauses = when_clauses
        @else_body = else_body
        @sub_instruction_ids = nil
      end
    end

    # Single when clause in a case statement
    # when 1, 2, 3 then body
    class WhenClause < Node
      attr_reader :conditions   # Array of HIR instructions (match values/ranges/classes)
      attr_reader :body         # Array of HIR instructions for the clause body

      def initialize(conditions: [], body: [])
        super(type: TypeChecker::Types::UNTYPED)
        @conditions = conditions
        @body = body
      end
    end

    # ========================================
    # Pattern Matching (case/in)
    # Ruby 3.0+ pattern matching support
    # ========================================

    # Case/in pattern matching statement
    # case x
    # in 1 then "one"
    # in Integer => n then n.to_s
    # in [a, b] then a + b
    # else "other"
    # end
    class CaseMatchStatement < Instruction
      attr_reader :predicate    # HIR instruction for the value being matched
      attr_reader :in_clauses   # Array of InClause
      attr_reader :else_body    # Array of HIR instructions for else branch (nil raises NoMatchingPatternError)

      def initialize(predicate:, in_clauses: [], else_body: nil, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @predicate = predicate
        @in_clauses = in_clauses
        @else_body = else_body
      end
    end

    # Single in clause in a case/in statement
    # in Pattern [if guard] then body
    class InClause < Node
      attr_reader :pattern    # Pattern node
      attr_reader :guard      # Optional guard expression (HIR instruction)
      attr_reader :body       # Array of HIR instructions for the clause body
      attr_reader :bindings   # Hash of { variable_name => type } for pattern variables

      def initialize(pattern:, guard: nil, body: [], bindings: {})
        super(type: TypeChecker::Types::UNTYPED)
        @pattern = pattern
        @guard = guard
        @body = body
        @bindings = bindings
      end
    end

    # Base class for pattern nodes
    class Pattern < Node
      attr_reader :bindings   # Hash of { variable_name => type } - variables bound by this pattern

      def initialize(bindings: {})
        super(type: TypeChecker::Types::UNTYPED)
        @bindings = bindings
      end
    end

    # Literal pattern: matches a specific value using ===
    # in 42 / in "hello" / in :symbol / in nil / in true / in false
    class LiteralPattern < Pattern
      attr_reader :value  # HIR Literal node (IntegerLit, StringLit, etc.)

      def initialize(value:, bindings: {})
        super(bindings: bindings)
        @value = value
      end
    end

    # Variable pattern: binds matched value to a variable
    # in x
    class VariablePattern < Pattern
      attr_reader :name       # Variable name (String)
      attr_reader :var_type   # Inferred type for the variable

      def initialize(name:, var_type: TypeChecker::Types::UNTYPED, bindings: nil)
        bindings ||= { name => var_type }
        super(bindings: bindings)
        @name = name
        @var_type = var_type
      end
    end

    # Constant/Type pattern: matches class or constant using ===
    # in Integer / in String / in MyClass
    class ConstantPattern < Pattern
      attr_reader :constant_name  # Constant name (String)
      attr_accessor :narrowed_type  # Type to narrow to in the matched branch

      def initialize(constant_name:, narrowed_type: nil, bindings: {})
        super(bindings: bindings)
        @constant_name = constant_name
        @narrowed_type = narrowed_type
      end
    end

    # Alternation pattern: matches any of several patterns
    # in 1 | 2 | 3 / in Integer | String
    class AlternationPattern < Pattern
      attr_reader :alternatives  # Array of Pattern nodes

      def initialize(alternatives:, bindings: {})
        super(bindings: bindings)
        @alternatives = alternatives
      end
    end

    # Array pattern: matches Array-like objects via deconstruct
    # in [a, b] / in [a, *rest] / in [*pre, x, *post]
    # in Point[x, y]
    class ArrayPattern < Pattern
      attr_reader :constant   # Optional constant for type check (String, e.g., "Point")
      attr_reader :requireds  # Required element patterns before rest (Array of Pattern)
      attr_reader :rest       # Rest pattern (*args), RestPattern or nil
      attr_reader :posts      # Post-rest required patterns (Array of Pattern)

      def initialize(constant: nil, requireds: [], rest: nil, posts: [], bindings: {})
        super(bindings: bindings)
        @constant = constant
        @requireds = requireds
        @rest = rest
        @posts = posts
      end
    end

    # Hash pattern: matches Hash-like objects via deconstruct_keys
    # in {x:, y:} / in {name: String => n}
    class HashPattern < Pattern
      attr_reader :constant   # Optional constant for type check (String)
      attr_reader :elements   # Array of HashPatternElement
      attr_reader :rest       # Rest pattern (**rest), RestPattern or nil

      def initialize(constant: nil, elements: [], rest: nil, bindings: {})
        super(bindings: bindings)
        @constant = constant
        @elements = elements
        @rest = rest
      end
    end

    # Single element in a hash pattern
    # x: or x: Pattern
    class HashPatternElement < Node
      attr_reader :key            # Symbol key (String)
      attr_reader :value_pattern  # Pattern for value (nil for shorthand `x:`)

      def initialize(key:, value_pattern: nil)
        super(type: TypeChecker::Types::UNTYPED)
        @key = key
        @value_pattern = value_pattern
      end
    end

    # Rest pattern: captures remaining elements
    # *rest or **rest or * or **
    class RestPattern < Pattern
      attr_reader :name  # Variable name (String), nil for anonymous * or **

      def initialize(name: nil, bindings: nil)
        bindings ||= name ? { name => TypeChecker::Types::ClassInstance.new(:Array) } : {}
        super(bindings: bindings)
        @name = name
      end
    end

    # Capture pattern: matches a pattern and binds to variable
    # in Integer => n / in [a, b] => arr
    class CapturePattern < Pattern
      attr_reader :value_pattern  # Pattern to match
      attr_reader :target         # Variable name to bind (String)

      def initialize(value_pattern:, target:, bindings: nil)
        # Merge bindings from value_pattern with the capture target
        pattern_bindings = value_pattern.bindings.dup
        pattern_bindings[target] = TypeChecker::Types::UNTYPED
        bindings ||= pattern_bindings
        super(bindings: bindings)
        @value_pattern = value_pattern
        @target = target
      end
    end

    # Pinned variable pattern: matches against existing variable value
    # in ^x
    class PinnedPattern < Pattern
      attr_reader :variable_name  # Variable name to match against (String)
      attr_reader :variable       # HIR LoadLocal instruction (populated during codegen)

      def initialize(variable_name:, variable: nil)
        super(bindings: {})
        @variable_name = variable_name
        @variable = variable
      end
    end

    # Match predicate expression: expr in pattern (returns true/false)
    # value in [a, b]
    class MatchPredicate < Instruction
      attr_reader :value    # Expression to match (HIR instruction)
      attr_reader :pattern  # Pattern to match against

      def initialize(value:, pattern:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @value = value
        @pattern = pattern
      end
    end

    # Match required expression: expr => pattern (raises NoMatchingPatternError on failure)
    # value => [a, b]
    class MatchRequired < Instruction
      attr_reader :value    # Expression to match (HIR instruction)
      attr_reader :pattern  # Pattern to match against

      def initialize(value:, pattern:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @value = value
        @pattern = pattern
      end
    end

    # Phi node (for SSA form)
    class Phi < Instruction
      attr_reader :incoming  # Hash of { block_label => value }

      def initialize(incoming:, type: TypeChecker::Types::UNTYPED, result_var: nil)
        super(type: type, result_var: result_var)
        @incoming = incoming
      end
    end

    # ========================================
    # NativeArray operations
    # Contiguous memory arrays with unboxed numeric elements
    # ========================================

    # Allocate a NativeArray
    # NativeArray[Float64] → double* with capacity
    class NativeArrayAlloc < Instruction
      attr_reader :size, :element_type

      def initialize(size:, element_type:, result_var: nil)
        array_type = TypeChecker::Types::NativeArrayType.new(element_type)
        super(type: array_type, result_var: result_var)
        @size = size  # HIR value (IntegerLit or LoadLocal)
        @element_type = element_type  # :Int64 or :Float64
      end
    end

    # Get element from NativeArray (unboxed)
    # arr[i] → double or i64
    class NativeArrayGet < Instruction
      attr_reader :array, :index, :element_type

      def initialize(array:, index:, element_type:, result_var: nil)
        elem_internal_type = case element_type
        when :Int64 then TypeChecker::Types::INTEGER
        when :Float64 then TypeChecker::Types::FLOAT
        else TypeChecker::Types::UNTYPED
        end
        super(type: elem_internal_type, result_var: result_var)
        @array = array  # HIR value (the NativeArray)
        @index = index  # HIR value (index)
        @element_type = element_type  # :Int64 or :Float64
      end
    end

    # Set element in NativeArray
    # arr[i] = value
    class NativeArraySet < Instruction
      attr_reader :array, :index, :value, :element_type

      def initialize(array:, index:, value:, element_type:)
        super(type: TypeChecker::Types::NIL)
        @array = array
        @index = index
        @value = value
        @element_type = element_type
      end
    end

    # Get length of NativeArray (stored with array metadata)
    class NativeArrayLength < Instruction
      attr_reader :array

      def initialize(array:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @array = array
      end
    end

    # ========================================
    # StaticArray operations
    # Fixed-size stack-allocated array with compile-time known size
    # ========================================

    # Allocate a StaticArray on stack
    # StaticArray[Float, 4].new() → stack-allocated [4 x double]
    class StaticArrayAlloc < Instruction
      attr_reader :element_type, :size, :initial_value

      def initialize(element_type:, size:, initial_value: nil, result_var: nil)
        array_type = TypeChecker::Types::StaticArrayType.new(element_type, size)
        super(type: array_type, result_var: result_var)
        @element_type = element_type  # :Int64 or :Float64
        @size = size                  # Compile-time constant integer
        @initial_value = initial_value  # Optional fill value (HIR value)
      end
    end

    # Get element from StaticArray (unboxed)
    # arr[i] → double or i64
    class StaticArrayGet < Instruction
      attr_reader :array, :index, :element_type, :size

      def initialize(array:, index:, element_type:, size:, result_var: nil)
        elem_internal_type = case element_type
        when :Int64 then TypeChecker::Types::INTEGER
        when :Float64 then TypeChecker::Types::FLOAT
        else TypeChecker::Types::UNTYPED
        end
        super(type: elem_internal_type, result_var: result_var)
        @array = array        # HIR value (the StaticArray pointer)
        @index = index        # HIR value (index)
        @element_type = element_type  # :Int64 or :Float64
        @size = size          # Compile-time size for bounds check optimization
      end
    end

    # Set element in StaticArray
    # arr[i] = value
    class StaticArraySet < Instruction
      attr_reader :array, :index, :value, :element_type, :size

      def initialize(array:, index:, value:, element_type:, size:)
        super(type: TypeChecker::Types::NIL)
        @array = array
        @index = index
        @value = value
        @element_type = element_type
        @size = size
      end
    end

    # Get size of StaticArray (compile-time constant)
    # arr.size → Integer (known at compile time)
    class StaticArraySize < Instruction
      attr_reader :array, :size

      def initialize(array:, size:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @array = array
        @size = size  # Compile-time known size
      end
    end

    # ========================================
    # ByteBuffer operations
    # Growable byte array for efficient I/O
    # ========================================

    # Allocate a new ByteBuffer
    # ByteBuffer.new(1024) → ptr to buffer struct
    class ByteBufferAlloc < Instruction
      attr_reader :capacity

      def initialize(capacity:, result_var: nil)
        super(type: TypeChecker::Types::BYTEBUFFER, result_var: result_var)
        @capacity = capacity  # HIR value for initial capacity
      end
    end

    # Get byte from ByteBuffer
    # buf[i] → Integer (0-255)
    class ByteBufferGet < Instruction
      attr_reader :buffer, :index

      def initialize(buffer:, index:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @buffer = buffer  # HIR value (the ByteBuffer)
        @index = index    # HIR value (index)
      end
    end

    # Set byte in ByteBuffer
    # buf[i] = byte
    class ByteBufferSet < Instruction
      attr_reader :buffer, :index, :byte

      def initialize(buffer:, index:, byte:)
        super(type: TypeChecker::Types::INTEGER)
        @buffer = buffer
        @index = index
        @byte = byte  # HIR value (0-255)
      end
    end

    # Get length of ByteBuffer
    class ByteBufferLength < Instruction
      attr_reader :buffer

      def initialize(buffer:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @buffer = buffer
      end
    end

    # Append to ByteBuffer
    # buf << byte, buf.write(string), buf.write_bytes(other_buf)
    class ByteBufferAppend < Instruction
      attr_reader :buffer, :value, :append_type

      # @param append_type [:byte, :string, :buffer]
      def initialize(buffer:, value:, append_type:, result_var: nil)
        super(type: TypeChecker::Types::BYTEBUFFER, result_var: result_var)
        @buffer = buffer
        @value = value
        @append_type = append_type
      end
    end

    # Search for byte or sequence in ByteBuffer
    # buf.index_of(32) → Integer? (finds ASCII space)
    # buf.index_of_seq("\r\n") → Integer?
    class ByteBufferIndexOf < Instruction
      attr_reader :buffer, :pattern, :search_type, :start_offset

      # @param search_type [:byte, :sequence]
      def initialize(buffer:, pattern:, search_type:, start_offset: nil, result_var: nil)
        super(type: TypeChecker::Types.optional(TypeChecker::Types::INTEGER), result_var: result_var)
        @buffer = buffer
        @pattern = pattern       # HIR value (byte integer or string)
        @search_type = search_type
        @start_offset = start_offset  # Optional start offset for search
      end
    end

    # Convert ByteBuffer to String
    # buf.to_s → String
    class ByteBufferToString < Instruction
      attr_reader :buffer, :ascii_only

      def initialize(buffer:, ascii_only: false, result_var: nil)
        super(type: TypeChecker::Types::STRING, result_var: result_var)
        @buffer = buffer
        @ascii_only = ascii_only  # Use faster ASCII conversion if true
      end
    end

    # Create ByteSlice from ByteBuffer
    # buf.slice(start, length) → ByteSlice
    class ByteBufferSlice < Instruction
      attr_reader :buffer, :start, :length

      def initialize(buffer:, start:, length:, result_var: nil)
        super(type: TypeChecker::Types::BYTESLICE, result_var: result_var)
        @buffer = buffer
        @start = start    # HIR value
        @length = length  # HIR value
      end
    end

    # ========================================
    # ByteSlice operations
    # Zero-copy view into ByteBuffer
    # ========================================

    # Get byte from ByteSlice
    class ByteSliceGet < Instruction
      attr_reader :slice, :index

      def initialize(slice:, index:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @slice = slice
        @index = index
      end
    end

    # Get length of ByteSlice
    class ByteSliceLength < Instruction
      attr_reader :slice

      def initialize(slice:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @slice = slice
      end
    end

    # Convert ByteSlice to String
    class ByteSliceToString < Instruction
      attr_reader :slice

      def initialize(slice:, result_var: nil)
        super(type: TypeChecker::Types::STRING, result_var: result_var)
        @slice = slice
      end
    end

    # ========================================
    # Slice[T] operations
    # Generic bounds-checked pointer view
    # ========================================

    # Allocate a new Slice with given size
    # Slice.new(10) → { ptr, size }
    class SliceAlloc < Instruction
      attr_reader :size, :element_type

      def initialize(size:, element_type:, result_var: nil)
        slice_type = TypeChecker::Types::SliceType.new(element_type)
        super(type: slice_type, result_var: result_var)
        @size = size  # HIR value
        @element_type = element_type  # :Int64 or :Float64
      end
    end

    # Get empty Slice singleton
    # Slice.empty → { null, 0 }
    class SliceEmpty < Instruction
      attr_reader :element_type

      def initialize(element_type:, result_var: nil)
        slice_type = TypeChecker::Types::SliceType.new(element_type)
        super(type: slice_type, result_var: result_var)
        @element_type = element_type
      end
    end

    # Get element from Slice (bounds-checked)
    # slice[i] → T
    class SliceGet < Instruction
      attr_reader :slice, :index, :element_type

      def initialize(slice:, index:, element_type:, result_var: nil)
        result_type = element_type == :Int64 ? TypeChecker::Types::INTEGER : TypeChecker::Types::FLOAT
        super(type: result_type, result_var: result_var)
        @slice = slice  # HIR value
        @index = index  # HIR value
        @element_type = element_type
      end
    end

    # Set element in Slice (bounds-checked)
    # slice[i] = value → value
    class SliceSet < Instruction
      attr_reader :slice, :index, :value, :element_type

      def initialize(slice:, index:, value:, element_type:, result_var: nil)
        result_type = element_type == :Int64 ? TypeChecker::Types::INTEGER : TypeChecker::Types::FLOAT
        super(type: result_type, result_var: result_var)
        @slice = slice
        @index = index
        @value = value
        @element_type = element_type
      end
    end

    # Get size of Slice
    # slice.size → Integer
    class SliceSize < Instruction
      attr_reader :slice

      def initialize(slice:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @slice = slice
      end
    end

    # Create subslice (view, no copy)
    # slice[start, count] → Slice[T]
    class SliceSubslice < Instruction
      attr_reader :slice, :start, :count, :element_type

      def initialize(slice:, start:, count:, element_type:, result_var: nil)
        slice_type = TypeChecker::Types::SliceType.new(element_type)
        super(type: slice_type, result_var: result_var)
        @slice = slice
        @start = start  # HIR value
        @count = count  # HIR value
        @element_type = element_type
      end
    end

    # Copy elements from another Slice
    # slice.copy_from(source) → self
    class SliceCopyFrom < Instruction
      attr_reader :dest, :source, :element_type

      def initialize(dest:, source:, element_type:, result_var: nil)
        slice_type = TypeChecker::Types::SliceType.new(element_type)
        super(type: slice_type, result_var: result_var)
        @dest = dest
        @source = source
        @element_type = element_type
      end
    end

    # Fill Slice with a value
    # slice.fill(value) → self
    class SliceFill < Instruction
      attr_reader :slice, :value, :element_type

      def initialize(slice:, value:, element_type:, result_var: nil)
        slice_type = TypeChecker::Types::SliceType.new(element_type)
        super(type: slice_type, result_var: result_var)
        @slice = slice
        @value = value  # HIR value
        @element_type = element_type
      end
    end

    # Convert NativeArray or StaticArray to Slice (zero-copy view)
    # array.to_slice → Slice[T]
    class ToSlice < Instruction
      attr_reader :source, :element_type, :source_kind

      # @param source [HIR value] NativeArray or StaticArray
      # @param element_type [Symbol] :Int64 or :Float64
      # @param source_kind [Symbol] :native_array or :static_array
      def initialize(source:, element_type:, source_kind:, result_var: nil)
        slice_type = TypeChecker::Types::SliceType.new(element_type)
        super(type: slice_type, result_var: result_var)
        @source = source
        @element_type = element_type
        @source_kind = source_kind
      end
    end

    # ========================================
    # StringBuffer operations
    # Efficient string building
    # ========================================

    # Allocate a new StringBuffer
    # StringBuffer.new(256) → VALUE (rb_str_buf_new result)
    class StringBufferAlloc < Instruction
      attr_reader :capacity

      def initialize(capacity:, result_var: nil)
        super(type: TypeChecker::Types::STRINGBUFFER, result_var: result_var)
        @capacity = capacity  # HIR value (nil for default)
      end
    end

    # Append to StringBuffer
    # buf << string
    class StringBufferAppend < Instruction
      attr_reader :buffer, :value

      def initialize(buffer:, value:, result_var: nil)
        super(type: TypeChecker::Types::STRINGBUFFER, result_var: result_var)
        @buffer = buffer
        @value = value  # HIR value (string to append)
      end
    end

    # Get current length of StringBuffer
    class StringBufferLength < Instruction
      attr_reader :buffer

      def initialize(buffer:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @buffer = buffer
      end
    end

    # Convert StringBuffer to String (returns the internal string)
    class StringBufferToString < Instruction
      attr_reader :buffer

      def initialize(buffer:, result_var: nil)
        super(type: TypeChecker::Types::STRING, result_var: result_var)
        @buffer = buffer
      end
    end

    # ========================================
    # NativeString operations
    # UTF-8 native string with byte and character level operations
    # Memory layout: { ptr (i8*), byte_len (i64), char_len (i64), flags (i64) }
    # ========================================

    # Create NativeString from Ruby String
    # NativeString.from(str) → NativeString
    class NativeStringFromRuby < Instruction
      attr_reader :string

      def initialize(string:, result_var: nil)
        super(type: TypeChecker::Types::NATIVESTRING, result_var: result_var)
        @string = string  # HIR value (Ruby String VALUE)
      end
    end

    # Get byte at index (O(1))
    # ns.byte_at(i) → Integer (0-255)
    class NativeStringByteAt < Instruction
      attr_reader :native_string, :index

      def initialize(native_string:, index:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @native_string = native_string
        @index = index
      end
    end

    # Get byte length (O(1))
    # ns.byte_length → Integer
    class NativeStringByteLength < Instruction
      attr_reader :native_string

      def initialize(native_string:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @native_string = native_string
      end
    end

    # Search for byte in NativeString
    # ns.byte_index_of(byte) → Integer?
    # ns.byte_index_of(byte, start_offset) → Integer?
    class NativeStringByteIndexOf < Instruction
      attr_reader :native_string, :byte, :start_offset

      def initialize(native_string:, byte:, start_offset: nil, result_var: nil)
        super(type: TypeChecker::Types.optional(TypeChecker::Types::INTEGER), result_var: result_var)
        @native_string = native_string
        @byte = byte  # HIR value (0-255)
        @start_offset = start_offset  # Optional HIR value
      end
    end

    # Create byte-level slice of NativeString
    # ns.byte_slice(start, length) → NativeString
    class NativeStringByteSlice < Instruction
      attr_reader :native_string, :start, :length

      def initialize(native_string:, start:, length:, result_var: nil)
        super(type: TypeChecker::Types::NATIVESTRING, result_var: result_var)
        @native_string = native_string
        @start = start    # HIR value (byte offset)
        @length = length  # HIR value (byte count)
      end
    end

    # Get character at index (UTF-8 aware, O(n) worst case)
    # ns.char_at(i) → String (single character)
    class NativeStringCharAt < Instruction
      attr_reader :native_string, :index

      def initialize(native_string:, index:, result_var: nil)
        super(type: TypeChecker::Types::STRING, result_var: result_var)
        @native_string = native_string
        @index = index  # Character index (not byte index)
      end
    end

    # Get character length (UTF-8 aware, cached after first call)
    # ns.char_length → Integer
    class NativeStringCharLength < Instruction
      attr_reader :native_string

      def initialize(native_string:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @native_string = native_string
      end
    end

    # Search for substring in NativeString
    # ns.char_index_of(needle) → Integer? (character index)
    class NativeStringCharIndexOf < Instruction
      attr_reader :native_string, :needle

      def initialize(native_string:, needle:, result_var: nil)
        super(type: TypeChecker::Types.optional(TypeChecker::Types::INTEGER), result_var: result_var)
        @native_string = native_string
        @needle = needle  # HIR value (String to find)
      end
    end

    # Create character-level slice of NativeString (UTF-8 aware)
    # ns.char_slice(start, length) → NativeString
    class NativeStringCharSlice < Instruction
      attr_reader :native_string, :start, :length

      def initialize(native_string:, start:, length:, result_var: nil)
        super(type: TypeChecker::Types::NATIVESTRING, result_var: result_var)
        @native_string = native_string
        @start = start    # HIR value (character offset)
        @length = length  # HIR value (character count)
      end
    end

    # Check if NativeString is ASCII-only (O(1) after creation)
    # ns.ascii_only? → bool
    class NativeStringAsciiOnly < Instruction
      attr_reader :native_string

      def initialize(native_string:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @native_string = native_string
      end
    end

    # Check if NativeString starts with prefix
    # ns.starts_with?(prefix) → bool
    class NativeStringStartsWith < Instruction
      attr_reader :native_string, :prefix

      def initialize(native_string:, prefix:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @native_string = native_string
        @prefix = prefix  # HIR value (String)
      end
    end

    # Check if NativeString ends with suffix
    # ns.ends_with?(suffix) → bool
    class NativeStringEndsWith < Instruction
      attr_reader :native_string, :suffix

      def initialize(native_string:, suffix:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @native_string = native_string
        @suffix = suffix  # HIR value (String)
      end
    end

    # Check if NativeString has valid UTF-8 encoding
    # ns.valid_encoding? → bool
    class NativeStringValidEncoding < Instruction
      attr_reader :native_string

      def initialize(native_string:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @native_string = native_string
      end
    end

    # Convert NativeString to Ruby String
    # ns.to_s → String
    class NativeStringToRuby < Instruction
      attr_reader :native_string

      def initialize(native_string:, result_var: nil)
        super(type: TypeChecker::Types::STRING, result_var: result_var)
        @native_string = native_string
      end
    end

    # Compare two NativeStrings
    # ns == other → bool
    class NativeStringCompare < Instruction
      attr_reader :native_string, :other

      def initialize(native_string:, other:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @native_string = native_string
        @other = other  # HIR value (NativeString)
      end
    end

    # ========================================
    # NativeClass operations
    # Fixed-layout structs with unboxed numeric fields
    # ========================================

    # Allocate a new NativeClass instance
    # Point.new → struct { double x; double y; }
    class NativeNew < Instruction
      attr_reader :class_type, :args

      def initialize(class_type:, result_var: nil, args: [])
        super(type: class_type, result_var: result_var)
        @class_type = class_type  # NativeClassType
        @args = args              # Constructor arguments (for JVM <init>)
      end
    end

    # Get field from NativeClass (unboxed)
    # point.x → double or i64
    class NativeFieldGet < Instruction
      attr_reader :object, :field_name, :class_type

      def initialize(object:, field_name:, class_type:, result_var: nil)
        field_type_tag = class_type.llvm_field_type_tag(field_name)
        internal_type = case field_type_tag
        when :i64 then TypeChecker::Types::INTEGER
        when :double then TypeChecker::Types::FLOAT
        else TypeChecker::Types::UNTYPED
        end
        super(type: internal_type, result_var: result_var)
        @object = object  # HIR value (the NativeClass instance)
        @field_name = field_name.to_sym
        @class_type = class_type  # NativeClassType
      end
    end

    # Set field in NativeClass
    # point.x = value
    class NativeFieldSet < Instruction
      attr_reader :object, :field_name, :value, :class_type

      def initialize(object:, field_name:, value:, class_type:)
        field_type_tag = class_type.llvm_field_type_tag(field_name)
        internal_type = case field_type_tag
        when :i64 then TypeChecker::Types::INTEGER
        when :double then TypeChecker::Types::FLOAT
        else TypeChecker::Types::UNTYPED
        end
        super(type: internal_type)
        @object = object
        @field_name = field_name.to_sym
        @value = value
        @class_type = class_type
      end
    end

    # Call a method on a NativeClass instance
    # Uses static dispatch (direct function call) instead of rb_funcallv
    # point.length_squared or point.add(other)
    class NativeMethodCall < Instruction
      attr_reader :receiver, :method_name, :args, :class_type, :method_sig, :owner_class

      # @param receiver [Instruction] The NativeClass instance
      # @param method_name [Symbol] Method name
      # @param args [Array<Instruction>] Arguments (excluding self)
      # @param class_type [NativeClassType] Type of receiver
      # @param method_sig [NativeMethodType] Method signature
      # @param owner_class [NativeClassType] Class that implements the method (may be superclass)
      # @param result_var [String, nil] Result variable name
      def initialize(receiver:, method_name:, args:, class_type:,
                     method_sig:, owner_class:, result_var: nil)
        # Determine return type from method signature
        return_type = if method_sig
          method_sig.return_type_as_internal
        else
          TypeChecker::Types::UNTYPED
        end
        super(type: return_type, result_var: result_var)
        @receiver = receiver
        @method_name = method_name.to_sym
        @args = args
        @class_type = class_type
        @method_sig = method_sig
        @owner_class = owner_class
      end
    end

    # Direct call to an external C function
    # Bypasses Ruby method dispatch entirely
    # Used for @cfunc annotated methods
    #
    # Example:
    #   # @cfunc "fast_sin" : (Float) -> Float
    #   def self.sin: (Float) -> Float
    #
    # Generates direct C function call without rb_funcallv
    class CFuncCall < Instruction
      attr_reader :c_func_name, :args, :cfunc_type

      # @param c_func_name [String] The C function name
      # @param args [Array<Instruction>] Arguments as HIR instructions
      # @param cfunc_type [CFuncType] The function type signature
      # @param result_var [String, nil] Result variable name
      def initialize(c_func_name:, args:, cfunc_type:, result_var: nil)
        return_type = cfunc_to_internal_type(cfunc_type.return_type)
        super(type: return_type, result_var: result_var)
        @c_func_name = c_func_name
        @args = args
        @cfunc_type = cfunc_type
      end

      private

      def cfunc_to_internal_type(type_sym)
        case type_sym
        when :Float then TypeChecker::Types::FLOAT
        when :Integer then TypeChecker::Types::INTEGER
        when :String then TypeChecker::Types::STRING
        when :Bool then TypeChecker::Types::BOOL
        when :void then TypeChecker::Types::NIL
        else TypeChecker::Types::UNTYPED
        end
      end
    end

    # ========================================
    # Extern class operations
    # External C struct wrapper operations
    # ========================================

    # Allocate an extern class wrapper (holds void* pointer)
    class ExternNew < Instruction
      attr_reader :extern_type

      # @param extern_type [ExternClassType] The extern class type
      # @param result_var [String, nil] Result variable name
      def initialize(extern_type:, result_var: nil)
        super(type: extern_type, result_var: result_var)
        @extern_type = extern_type
      end
    end

    # Call extern class constructor (singleton method returning opaque pointer)
    # Example: db = SQLiteDB.open("test.db")
    class ExternConstructorCall < Instruction
      attr_reader :extern_type, :c_func_name, :args, :method_sig

      # @param extern_type [ExternClassType] The extern class type
      # @param c_func_name [String] C function name to call
      # @param args [Array<Instruction>] Arguments as HIR instructions
      # @param method_sig [ExternMethodType] Method signature
      # @param result_var [String, nil] Result variable name
      def initialize(extern_type:, c_func_name:, args:, method_sig:, result_var: nil)
        super(type: extern_type, result_var: result_var)
        @extern_type = extern_type
        @c_func_name = c_func_name
        @args = args
        @method_sig = method_sig
      end
    end

    # Call extern class instance method (passes opaque pointer as first arg)
    # Example: results = db.execute("SELECT * FROM users")
    class ExternMethodCall < Instruction
      attr_reader :receiver, :c_func_name, :args, :extern_type, :method_sig

      # @param receiver [Instruction, String] Receiver (extern class instance)
      # @param c_func_name [String] C function name to call
      # @param args [Array<Instruction>] Arguments (excluding opaque pointer)
      # @param extern_type [ExternClassType] The extern class type
      # @param method_sig [ExternMethodType] Method signature
      # @param result_var [String, nil] Result variable name
      def initialize(receiver:, c_func_name:, args:, extern_type:, method_sig:, result_var: nil)
        return_type = extern_to_internal_type(method_sig.return_type)
        super(type: return_type, result_var: result_var)
        @receiver = receiver
        @c_func_name = c_func_name
        @args = args
        @extern_type = extern_type
        @method_sig = method_sig
      end

      private

      def extern_to_internal_type(type_sym)
        case type_sym
        when :Float then TypeChecker::Types::FLOAT
        when :Integer then TypeChecker::Types::INTEGER
        when :String then TypeChecker::Types::STRING
        when :Bool then TypeChecker::Types::BOOL
        when :Array then TypeChecker::Types::ClassInstance.new(:Array)
        when :Hash then TypeChecker::Types::ClassInstance.new(:Hash)
        when :void then TypeChecker::Types::NIL
        when :ptr then TypeChecker::Types::UNTYPED
        else TypeChecker::Types::UNTYPED
        end
      end
    end

    # ========================================
    # SIMD class operations
    # Fixed-size vector operations for @simd classes
    # ========================================

    # Allocate a new SIMD class instance (zero-initialized vector)
    class SIMDNew < Instruction
      attr_reader :simd_type

      # @param simd_type [SIMDClassType] The SIMD class type
      # @param result_var [String, nil] Result variable name
      def initialize(simd_type:, result_var: nil)
        super(type: simd_type, result_var: result_var)
        @simd_type = simd_type
      end
    end

    # Get field from SIMD class (extract element from vector)
    class SIMDFieldGet < Instruction
      attr_reader :object, :field_name, :simd_type

      # @param object [Instruction, String] SIMD class instance
      # @param field_name [Symbol] Field name (e.g., :x, :y, :z, :w)
      # @param simd_type [SIMDClassType] The SIMD class type
      # @param result_var [String, nil] Result variable name
      def initialize(object:, field_name:, simd_type:, result_var: nil)
        super(type: TypeChecker::Types::FLOAT, result_var: result_var)
        @object = object
        @field_name = field_name.to_sym
        @simd_type = simd_type
      end
    end

    # Set field in SIMD class (insert element into vector)
    class SIMDFieldSet < Instruction
      attr_reader :object, :field_name, :value, :simd_type

      # @param object [Instruction, String] SIMD class instance
      # @param field_name [Symbol] Field name (e.g., :x, :y, :z, :w)
      # @param value [Instruction, String] Value to set
      # @param simd_type [SIMDClassType] The SIMD class type
      def initialize(object:, field_name:, value:, simd_type:)
        super(type: TypeChecker::Types::FLOAT)
        @object = object
        @field_name = field_name.to_sym
        @value = value
        @simd_type = simd_type
      end
    end

    # Call a method on SIMD class (vector arithmetic operation)
    class SIMDMethodCall < Instruction
      attr_reader :receiver, :method_name, :args, :simd_type, :method_sig

      # @param receiver [Instruction, String] SIMD class instance
      # @param method_name [Symbol] Method name (e.g., :add, :dot, :scale)
      # @param args [Array<Instruction>] Arguments
      # @param simd_type [SIMDClassType] The SIMD class type
      # @param method_sig [NativeMethodType, nil] Method signature
      # @param result_var [String, nil] Result variable name
      def initialize(receiver:, method_name:, args:, simd_type:, method_sig: nil, result_var: nil)
        # Determine return type: scalar (Float64) or vector (Self)
        return_type = if method_sig&.return_type == :Float64
          TypeChecker::Types::FLOAT
        else
          simd_type
        end
        super(type: return_type, result_var: result_var)
        @receiver = receiver
        @method_name = method_name.to_sym
        @args = args
        @simd_type = simd_type
        @method_sig = method_sig
      end
    end

    # ========================================
    # JSON operations (yyjson-based)
    # Direct JSON parsing to NativeClass without VALUE conversion overhead
    # ========================================

    # Parse JSON string directly into a NativeClass
    # KonpeitoJSON.parse_as(json_string, User) → User (NativeClass)
    # Avoids VALUE conversion for unboxed fields (Integer, Float, Bool)
    class JSONParseAs < Instruction
      attr_reader :json_expr, :target_class

      # @param json_expr [Instruction] HIR expression for JSON string
      # @param target_class [NativeClassType] Target NativeClass type
      # @param result_var [String, nil] Result variable name
      def initialize(json_expr:, target_class:, result_var: nil)
        super(type: target_class, result_var: result_var)
        @json_expr = json_expr
        @target_class = target_class
      end
    end

    # Parse JSON array directly into a NativeArray
    # KonpeitoJSON.parse_array_as(json_string, User) → NativeArray[User]
    class JSONParseArrayAs < Instruction
      attr_reader :json_expr, :element_class

      # @param json_expr [Instruction] HIR expression for JSON string
      # @param element_class [NativeClassType] Element NativeClass type
      # @param result_var [String, nil] Result variable name
      def initialize(json_expr:, element_class:, result_var: nil)
        array_type = TypeChecker::Types::NativeArrayType.new(element_class)
        super(type: array_type, result_var: result_var)
        @json_expr = json_expr
        @element_class = element_class
      end
    end

    # ========================================
    # NativeHash operations
    # Generic hash with Robin Hood hashing
    # Memory layout: { buckets (ptr), size (i64), capacity (i64) }
    # Each bucket: { hash (i64), key (K), value (V), state (i8) }
    # ========================================

    # Allocate a new NativeHash
    # NativeHashStringInteger.new(capacity) → NativeHash[String, Integer]
    class NativeHashAlloc < Instruction
      attr_reader :key_type, :value_type, :capacity

      # @param key_type [Symbol] :String, :Symbol, or :Integer
      # @param value_type [Symbol, NativeClassType] Value type
      # @param capacity [Instruction, nil] Optional initial capacity
      def initialize(key_type:, value_type:, capacity: nil, result_var: nil)
        hash_type = TypeChecker::Types::NativeHashType.new(key_type, value_type)
        super(type: hash_type, result_var: result_var)
        @key_type = key_type
        @value_type = value_type
        @capacity = capacity  # HIR value (nil for default 16)
      end
    end

    # Get value from NativeHash
    # hash[key] → V | nil
    class NativeHashGet < Instruction
      attr_reader :hash_var, :key, :key_type, :value_type

      def initialize(hash_var:, key:, key_type:, value_type:, result_var: nil)
        # Result is the value type (nullable)
        result_type = case value_type
                      when :Integer then TypeChecker::Types::INTEGER
                      when :Float then TypeChecker::Types::FLOAT
                      when :Bool then TypeChecker::Types::BOOL
                      when :String, :Object, :Array, :Hash then TypeChecker::Types::ClassInstance.new(value_type)
                      else
                        # NativeClass
                        value_type
                      end
        super(type: result_type, result_var: result_var)
        @hash_var = hash_var  # HIR value
        @key = key            # HIR value
        @key_type = key_type
        @value_type = value_type
      end
    end

    # Set value in NativeHash
    # hash[key] = value → value
    class NativeHashSet < Instruction
      attr_reader :hash_var, :key, :value, :key_type, :value_type

      def initialize(hash_var:, key:, value:, key_type:, value_type:, result_var: nil)
        result_type = case value_type
                      when :Integer then TypeChecker::Types::INTEGER
                      when :Float then TypeChecker::Types::FLOAT
                      when :Bool then TypeChecker::Types::BOOL
                      when :String, :Object, :Array, :Hash then TypeChecker::Types::ClassInstance.new(value_type)
                      else
                        value_type
                      end
        super(type: result_type, result_var: result_var)
        @hash_var = hash_var
        @key = key
        @value = value
        @key_type = key_type
        @value_type = value_type
      end
    end

    # Get size of NativeHash
    # hash.size → Integer
    class NativeHashSize < Instruction
      attr_reader :hash_var

      def initialize(hash_var:, result_var: nil)
        super(type: TypeChecker::Types::INTEGER, result_var: result_var)
        @hash_var = hash_var
      end
    end

    # Check if key exists in NativeHash
    # hash.has_key?(key) → bool
    class NativeHashHasKey < Instruction
      attr_reader :hash_var, :key, :key_type

      def initialize(hash_var:, key:, key_type:, result_var: nil)
        super(type: TypeChecker::Types::BOOL, result_var: result_var)
        @hash_var = hash_var
        @key = key
        @key_type = key_type
      end
    end

    # Delete key from NativeHash
    # hash.delete(key) → V | nil
    class NativeHashDelete < Instruction
      attr_reader :hash_var, :key, :key_type, :value_type

      def initialize(hash_var:, key:, key_type:, value_type:, result_var: nil)
        result_type = case value_type
                      when :Integer then TypeChecker::Types::INTEGER
                      when :Float then TypeChecker::Types::FLOAT
                      when :Bool then TypeChecker::Types::BOOL
                      when :String, :Object, :Array, :Hash then TypeChecker::Types::ClassInstance.new(value_type)
                      else
                        value_type
                      end
        super(type: result_type, result_var: result_var)
        @hash_var = hash_var
        @key = key
        @key_type = key_type
        @value_type = value_type
      end
    end

    # Clear all entries from NativeHash
    # hash.clear → self
    class NativeHashClear < Instruction
      attr_reader :hash_var, :key_type, :value_type

      def initialize(hash_var:, key_type:, value_type:, result_var: nil)
        hash_type = TypeChecker::Types::NativeHashType.new(key_type, value_type)
        super(type: hash_type, result_var: result_var)
        @hash_var = hash_var
        @key_type = key_type
        @value_type = value_type
      end
    end

    # Get all keys from NativeHash
    # hash.keys → Array[K]
    class NativeHashKeys < Instruction
      attr_reader :hash_var, :key_type

      def initialize(hash_var:, key_type:, result_var: nil)
        # Returns Array of keys (Ruby Array, not NativeArray)
        super(type: TypeChecker::Types::ClassInstance.new(:Array), result_var: result_var)
        @hash_var = hash_var
        @key_type = key_type
      end
    end

    # Get all values from NativeHash
    # hash.values → Array[V]
    class NativeHashValues < Instruction
      attr_reader :hash_var, :key_type, :value_type

      def initialize(hash_var:, key_type:, value_type:, result_var: nil)
        # Returns Array of values (Ruby Array)
        super(type: TypeChecker::Types::ClassInstance.new(:Array), result_var: result_var)
        @hash_var = hash_var
        @key_type = key_type
        @value_type = value_type
      end
    end

    # Iterate over NativeHash entries
    # hash.each { |k, v| ... }
    class NativeHashEach < Instruction
      attr_reader :hash_var, :key_type, :value_type, :block_params, :block_body

      def initialize(hash_var:, key_type:, value_type:, block_params:, block_body:, result_var: nil)
        hash_type = TypeChecker::Types::NativeHashType.new(key_type, value_type)
        super(type: hash_type, result_var: result_var)
        @hash_var = hash_var
        @key_type = key_type
        @value_type = value_type
        @block_params = block_params  # Array of param names [key_var, value_var]
        @block_body = block_body      # Array of BasicBlocks
      end
    end
  end
end

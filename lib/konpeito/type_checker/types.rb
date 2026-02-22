# frozen_string_literal: true

module Konpeito
  module TypeChecker
    # Internal type representation for the compiler
    module Types
      # Base class for all types
      class Type
        def ==(other)
          self.class == other.class
        end

        def hash
          self.class.hash
        end

        def eql?(other)
          self == other
        end

        def untyped?
          false
        end

        def union?
          false
        end

        # Check if this type can be used where `other` is expected
        def subtype_of?(other)
          return true if other.is_a?(Untyped)
          return true if self == other
          false
        end
      end

      # Unknown/any type
      class Untyped < Type
        def to_s
          "untyped"
        end

        def untyped?
          true
        end

        def subtype_of?(_other)
          true
        end
      end

      # Bottom type (no possible value)
      class Bottom < Type
        def to_s
          "bot"
        end

        def subtype_of?(_other)
          true
        end
      end

      # Nil type
      class NilType < Type
        def to_s
          "nil"
        end
      end

      # Boolean type (true | false)
      class BoolType < Type
        def to_s
          "bool"
        end
      end

      # Represents a specific class instance
      class ClassInstance < Type
        attr_reader :name, :type_args

        def initialize(name, type_args = [])
          @name = name.to_sym
          @type_args = type_args
        end

        def ==(other)
          return false unless other.is_a?(ClassInstance)
          name == other.name && type_args == other.type_args
        end

        def hash
          [name, type_args].hash
        end

        def to_s
          if type_args.empty?
            name.to_s
          else
            "#{name}[#{type_args.map(&:to_s).join(", ")}]"
          end
        end

        def subtype_of?(other)
          return true if super
          return false unless other.is_a?(ClassInstance)
          return true if name == other.name

          # Check both built-in and user-defined class hierarchy
          ancestors = ClassInstance.lookup_hierarchy(name)
          return false unless ancestors
          ancestors.include?(other.name.to_sym)
        end

        # Get ancestors list for a class (both built-in and user-defined)
        def self.lookup_hierarchy(class_name)
          CLASS_HIERARCHY[class_name.to_sym] || @@user_class_hierarchy[class_name.to_sym]
        end

        # Register user-defined class hierarchy
        def self.register_class_hierarchy(class_name, ancestors)
          @@user_class_hierarchy[class_name.to_sym] = ancestors.map(&:to_sym)
        end

        # Reset user-defined hierarchies (for test isolation)
        def self.reset_user_hierarchy!
          @@user_class_hierarchy.clear
        end

        # Find LUB (Least Upper Bound) of two class types
        def self.find_lub(t1, t2)
          return nil unless t1.is_a?(ClassInstance) && t2.is_a?(ClassInstance)

          ancestors1 = [t1.name] + (lookup_hierarchy(t1.name) || [:Object])
          ancestors2 = [t2.name] + (lookup_hierarchy(t2.name) || [:Object])

          # Find first common ancestor
          ancestors1.each do |a|
            return ClassInstance.new(a) if ancestors2.include?(a)
          end
          ClassInstance.new(:Object)
        end

        # User-defined class hierarchies (mutable, unlike CLASS_HIERARCHY)
        @@user_class_hierarchy = {}

        # Basic Ruby class hierarchy
        CLASS_HIERARCHY = {
          Integer: [:Numeric, :Comparable, :Object, :BasicObject],
          Float: [:Numeric, :Comparable, :Object, :BasicObject],
          Rational: [:Numeric, :Comparable, :Object, :BasicObject],
          Complex: [:Numeric, :Object, :BasicObject],
          Numeric: [:Comparable, :Object, :BasicObject],
          String: [:Comparable, :Object, :BasicObject],
          Symbol: [:Comparable, :Object, :BasicObject],
          Array: [:Object, :BasicObject],
          Hash: [:Object, :BasicObject],
          TrueClass: [:Object, :BasicObject],
          FalseClass: [:Object, :BasicObject],
          NilClass: [:Object, :BasicObject],
          Range: [:Object, :BasicObject],
          Regexp: [:Object, :BasicObject],
          Proc: [:Object, :BasicObject],
          Fiber: [:Object, :BasicObject],
          Thread: [:Object, :BasicObject],
          Mutex: [:Object, :BasicObject],
          Queue: [:Object, :BasicObject],
          SizedQueue: [:Queue, :Object, :BasicObject],
          ConditionVariable: [:Object, :BasicObject],
          Time: [:Object, :BasicObject],
          StandardError: [:Exception, :Object, :BasicObject],
          RuntimeError: [:StandardError, :Exception, :Object, :BasicObject],
          TypeError: [:StandardError, :Exception, :Object, :BasicObject],
          ArgumentError: [:StandardError, :Exception, :Object, :BasicObject],
          NameError: [:StandardError, :Exception, :Object, :BasicObject],
          NoMethodError: [:NameError, :StandardError, :Exception, :Object, :BasicObject],
          IOError: [:StandardError, :Exception, :Object, :BasicObject],
          ZeroDivisionError: [:StandardError, :Exception, :Object, :BasicObject],
          Exception: [:Object, :BasicObject],
          Object: [:BasicObject],
          BasicObject: [],
        }.freeze
      end

      # Represents a class/module itself (for class method calls)
      # e.g., when we write `NativeHash.new`, the receiver type is ClassSingleton(:NativeHash)
      class ClassSingleton < Type
        attr_reader :name

        def initialize(name)
          @name = name.to_sym
        end

        def ==(other)
          return false unless other.is_a?(ClassSingleton)
          name == other.name
        end

        def hash
          [:singleton, name].hash
        end

        def to_s
          "singleton(#{name})"
        end
      end

      # Union of types (A | B)
      class Union < Type
        attr_reader :types

        def initialize(types)
          @types = types.uniq
        end

        def ==(other)
          return false unless other.is_a?(Union)
          types.sort_by(&:to_s) == other.types.sort_by(&:to_s)
        end

        def hash
          types.map(&:hash).sort.hash
        end

        def union?
          true
        end

        def to_s
          types.map(&:to_s).join(" | ")
        end

        def subtype_of?(other)
          return true if super
          return types.all? { |t| t.subtype_of?(other) } unless other.is_a?(Union)
          types.all? { |t| other.types.any? { |o| t.subtype_of?(o) } }
        end
      end

      # Intersection of types (A & B)
      class Intersection < Type
        attr_reader :types

        def initialize(types)
          @types = types.uniq
        end

        def ==(other)
          return false unless other.is_a?(Intersection)
          types.sort_by(&:to_s) == other.types.sort_by(&:to_s)
        end

        def hash
          types.map(&:hash).sort.hash
        end

        def to_s
          types.map(&:to_s).join(" & ")
        end
      end

      # Proc/Lambda type
      class ProcType < Type
        attr_reader :param_types, :return_type

        def initialize(param_types, return_type)
          @param_types = param_types
          @return_type = return_type
        end

        def ==(other)
          return false unless other.is_a?(ProcType)
          param_types == other.param_types && return_type == other.return_type
        end

        def hash
          [param_types, return_type].hash
        end

        def to_s
          params = param_types.map(&:to_s).join(", ")
          "^(#{params}) -> #{return_type}"
        end
      end

      # NativeArray type - contiguous memory array with unboxed elements
      # Supports numeric types (Int64, Float64) and NativeClass types
      class NativeArrayType < Type
        attr_reader :element_type

        # Allowed primitive element types for NativeArray
        ALLOWED_PRIMITIVES = %i[Int64 Float64].freeze

        # @param element_type [Symbol, NativeClassType] Element type
        def initialize(element_type)
          @element_type = element_type
          validate_element_type!
        end

        def ==(other)
          return false unless other.is_a?(NativeArrayType)
          element_type == other.element_type
        end

        def hash
          elem_hash = native_class_element? ? element_type.name : element_type
          [:NativeArray, elem_hash].hash
        end

        def to_s
          elem_str = native_class_element? ? element_type.name : element_type
          "NativeArray[#{elem_str}]"
        end

        def int64?
          element_type == :Int64
        end

        def float64?
          element_type == :Float64
        end

        def native_class_element?
          element_type.is_a?(NativeClassType)
        end

        def primitive_element?
          ALLOWED_PRIMITIVES.include?(element_type)
        end

        # Get LLVM type tag for primitive elements
        def llvm_element_type_tag
          return :native_class if native_class_element?
          int64? ? :i64 : :double
        end

        private

        def validate_element_type!
          return if ALLOWED_PRIMITIVES.include?(element_type)
          return if element_type.is_a?(NativeClassType)

          raise ArgumentError,
            "NativeArray only supports #{ALLOWED_PRIMITIVES.join(', ')} or NativeClass, got #{element_type}"
        end
      end

      # StaticArray type - fixed-size stack-allocated array with compile-time size
      # Similar to NativeArray but size is known at compile time
      # Enables stack allocation (no heap) and potential optimizations
      class StaticArrayType < Type
        attr_reader :element_type, :size

        # Allowed primitive element types for StaticArray
        ALLOWED_PRIMITIVES = %i[Int64 Float64].freeze

        # @param element_type [Symbol] Element type (:Int64 or :Float64)
        # @param size [Integer] Array size (compile-time constant)
        def initialize(element_type, size)
          @element_type = element_type
          @size = size
          validate!
        end

        def ==(other)
          return false unless other.is_a?(StaticArrayType)
          element_type == other.element_type && size == other.size
        end

        def hash
          [:StaticArray, element_type, size].hash
        end

        def to_s
          "StaticArray[#{element_type}, #{size}]"
        end

        def int64?
          element_type == :Int64
        end

        def float64?
          element_type == :Float64
        end

        # Get LLVM type tag for elements
        def llvm_element_type_tag
          int64? ? :i64 : :double
        end

        # Get total byte size
        def byte_size
          size * 8  # 8 bytes per element (i64 or double)
        end

        private

        def validate!
          unless ALLOWED_PRIMITIVES.include?(element_type)
            raise ArgumentError,
              "StaticArray only supports #{ALLOWED_PRIMITIVES.join(', ')}, got #{element_type}"
          end
          unless size.is_a?(Integer) && size > 0
            raise ArgumentError, "StaticArray size must be a positive integer, got #{size}"
          end
        end
      end

      # ByteBuffer type - growable byte array for efficient I/O operations
      # Provides direct memory access and search operations (memchr)
      # Used for HTTP request/response parsing and building
      class ByteBufferType < Type
        attr_reader :capacity

        # @param capacity [Integer, nil] Optional capacity hint (nil = dynamic)
        def initialize(capacity: nil)
          @capacity = capacity
        end

        def ==(other)
          other.is_a?(ByteBufferType)
        end

        def hash
          :ByteBuffer.hash
        end

        def to_s
          capacity ? "ByteBuffer[#{capacity}]" : "ByteBuffer"
        end

        def static_capacity?
          !@capacity.nil?
        end
      end

      # ByteSlice type - zero-copy view into a ByteBuffer
      # Provides read-only access to a portion of buffer memory
      class ByteSliceType < Type
        def ==(other)
          other.is_a?(ByteSliceType)
        end

        def hash
          :ByteSlice.hash
        end

        def to_s
          "ByteSlice"
        end
      end

      # Slice[T] type - bounds-checked pointer view to contiguous memory
      # Generic version of ByteSlice supporting Int64 and Float64 elements
      # Memory layout: { ptr, size } - 16 bytes on 64-bit systems
      # Used for zero-copy views into NativeArray and StaticArray
      class SliceType < Type
        attr_reader :element_type

        # Allowed primitive element types for Slice
        ALLOWED_PRIMITIVES = %i[Int64 Float64].freeze

        # @param element_type [Symbol] Element type (:Int64 or :Float64)
        def initialize(element_type)
          @element_type = element_type
          validate!
        end

        def ==(other)
          return false unless other.is_a?(SliceType)
          element_type == other.element_type
        end

        def hash
          [:Slice, element_type].hash
        end

        def to_s
          "Slice[#{element_type}]"
        end

        def int64?
          element_type == :Int64
        end

        def float64?
          element_type == :Float64
        end

        # Get LLVM type tag for elements
        def llvm_element_type_tag
          int64? ? :i64 : :double
        end

        # Get element size in bytes
        def element_size
          8  # Both i64 and double are 8 bytes
        end

        private

        def validate!
          unless ALLOWED_PRIMITIVES.include?(element_type)
            raise ArgumentError,
              "Slice only supports #{ALLOWED_PRIMITIVES.join(', ')}, got #{element_type}"
          end
        end
      end

      # NativeHash[K, V] type - typed hash map with unboxed values
      # Supports String/Symbol/Integer keys and Integer/Float/Bool/String/NativeClass values
      # Memory layout: { capacity: i64, size: i64, buckets: ptr } - 24 bytes header
      # Uses Robin Hood hashing for efficient lookup
      class NativeHashType < Type
        attr_reader :key_type, :value_type

        # Allowed key types (must be hashable)
        ALLOWED_KEY_TYPES = %i[String Symbol Integer].freeze

        # Allowed primitive value types (unboxed)
        ALLOWED_PRIMITIVE_VALUES = %i[Integer Float Bool].freeze

        # Ruby object value types (boxed, require GC marking)
        RUBY_OBJECT_VALUES = %i[String Object Array Hash].freeze

        # @param key_type [Symbol] Key type (:String, :Symbol, :Integer)
        # @param value_type [Symbol, NativeClassType] Value type
        def initialize(key_type, value_type)
          @key_type = key_type.to_sym
          @value_type = value_type.is_a?(NativeClassType) ? value_type : value_type.to_sym
          validate!
        end

        def ==(other)
          return false unless other.is_a?(NativeHashType)
          key_type == other.key_type && value_type == other.value_type
        end

        def hash
          val_hash = native_class_value? ? value_type.name : value_type
          [:NativeHash, key_type, val_hash].hash
        end

        def to_s
          val_str = native_class_value? ? value_type.name : value_type
          "NativeHash[#{key_type}, #{val_str}]"
        end

        # Check if key type is String
        def string_key?
          key_type == :String
        end

        # Check if key type is Symbol
        def symbol_key?
          key_type == :Symbol
        end

        # Check if key type is Integer
        def integer_key?
          key_type == :Integer
        end

        # Check if value type is a primitive (unboxed)
        def primitive_value?
          ALLOWED_PRIMITIVE_VALUES.include?(value_type)
        end

        # Check if value type is a NativeClass
        def native_class_value?
          value_type.is_a?(NativeClassType)
        end

        # Check if value type is a Ruby object (boxed)
        def ruby_object_value?
          RUBY_OBJECT_VALUES.include?(value_type)
        end

        # Get LLVM type tag for key
        def llvm_key_type_tag
          case key_type
          when :String then :value  # Ruby String VALUE
          when :Symbol then :i64    # Symbol ID
          when :Integer then :i64   # Unboxed integer
          end
        end

        # Get LLVM type tag for value
        def llvm_value_type_tag
          case value_type
          when :Integer then :i64
          when :Float then :double
          when :Bool then :i8
          when :String, :Object, :Array, :Hash then :value
          else
            native_class_value? ? :native_class : :value
          end
        end

        # Get key size in bytes
        def key_size
          8  # All key types are 8 bytes (VALUE or i64)
        end

        # Get value size in bytes
        def value_size
          case value_type
          when :Bool then 1
          else 8  # i64, double, or VALUE pointer
          end
        end

        # Get entry size in bytes (hash + key + value + state, aligned)
        def entry_size
          # hash(8) + key(8) + value(8) + state(1) + padding(7) = 32
          32
        end

        private

        def validate!
          unless ALLOWED_KEY_TYPES.include?(key_type)
            raise ArgumentError,
              "NativeHash key must be #{ALLOWED_KEY_TYPES.join(', ')}, got #{key_type}"
          end

          unless primitive_value? || ruby_object_value? || native_class_value?
            raise ArgumentError,
              "NativeHash value must be a primitive, Ruby object, or NativeClass, got #{value_type}"
          end
        end
      end

      # StringBuffer type - efficient string building with pre-allocation
      # Wraps CRuby's rb_str_buf_new for optimized string concatenation
      class StringBufferType < Type
        attr_reader :capacity

        # @param capacity [Integer, nil] Optional initial capacity
        def initialize(capacity: nil)
          @capacity = capacity
        end

        def ==(other)
          other.is_a?(StringBufferType)
        end

        def hash
          :StringBuffer.hash
        end

        def to_s
          capacity ? "StringBuffer[#{capacity}]" : "StringBuffer"
        end
      end

      # NativeString type - UTF-8 native string with optimized operations
      # Provides both byte-level (O(1)) and character-level (UTF-8 aware) operations
      # Memory layout: { ptr (i8*), byte_len (i64), char_len (i64), flags (i64) }
      # Flags: bit 0 = ASCII_ONLY (when set, byte_len == char_len)
      class NativeStringType < Type
        # Encoding mode for the string
        ENCODING_UTF8 = :utf8
        ENCODING_ASCII = :ascii

        def ==(other)
          other.is_a?(NativeStringType)
        end

        def hash
          :NativeString.hash
        end

        def to_s
          "NativeString"
        end

        # Check if this is known to be ASCII-only at compile time
        # Runtime check uses ascii_only? method
        def ascii_only?
          false  # Conservative default; runtime determines actual encoding
        end
      end

      # NativeClass type - fixed layout struct with unboxed numeric fields
      # Marked with @native annotation in RBS
      # Supports Wren-style single inheritance and instance methods
      # Optionally supports vtable polymorphism with @native vtable annotation
      # Can be marked as value type with @struct annotation for pass-by-value semantics
      class NativeClassType < Type
        attr_reader :name, :fields, :methods, :superclass
        attr_accessor :vtable, :is_value_type

        # Allowed primitive field types for NativeClass (unboxed)
        ALLOWED_PRIMITIVE_TYPES = %i[Int64 Float64 Bool].freeze

        # Ruby object field types (boxed, require GC marking)
        RUBY_OBJECT_TYPES = %i[String Object Array Hash].freeze

        # @param name [Symbol] Class name
        # @param fields [Hash{Symbol => Symbol}] Field name -> type (:Int64, :Float64, :Bool, or NativeClass name)
        # @param methods [Hash{Symbol => NativeMethodType}] Method name -> signature
        # @param superclass [Symbol, nil] Superclass name (nil for root classes)
        # @param vtable [Boolean] Whether to use vtable for dynamic dispatch
        # @param is_value_type [Boolean] Whether this is a value type (@struct annotation)
        # @param native_class_registry [Hash{Symbol => NativeClassType}] Registry for validating embedded types
        def initialize(name, fields = {}, methods = {}, superclass: nil, vtable: false, is_value_type: false, native_class_registry: nil)
          @name = name.to_sym
          @fields = fields
          @methods = methods
          @superclass = superclass&.to_sym
          @vtable = vtable
          @is_value_type = is_value_type
          @native_class_registry = native_class_registry
          # Validation is deferred - call validate_fields! after all classes are registered
        end

        # Set registry for field validation (called after all classes are parsed)
        def native_class_registry=(registry)
          @native_class_registry = registry
        end

        def ==(other)
          return false unless other.is_a?(NativeClassType)
          name == other.name && fields == other.fields && superclass == other.superclass && vtable == other.vtable
        end

        def hash
          [name, fields, superclass, vtable].hash
        end

        # Check if this class uses vtable dispatch (or inherits from one that does)
        def uses_vtable?(registry = nil)
          return true if @vtable
          return false unless @superclass

          reg = registry || @native_class_registry || {}
          parent = reg[@superclass]
          parent&.uses_vtable?(reg) || false
        end

        # Get all methods for vtable layout (parent methods first, then own methods)
        # Method order is important: parent class methods must be at the same index
        # in child vtables for polymorphism to work correctly.
        # @param registry [Hash{Symbol => NativeClassType}] Registry of all native classes
        # @return [Array<[Symbol, NativeMethodType, Symbol]>] Array of [method_name, method_sig, owner_class_name]
        def vtable_methods(registry)
          inherited = if @superclass
            parent = registry[@superclass]
            parent ? parent.vtable_methods(registry) : []
          else
            []
          end

          # Build own methods list, excluding those already in parent vtable
          parent_method_names = inherited.map { |m| m[0] }.to_set
          own = @methods.map do |method_name, method_sig|
            [method_name, method_sig, @name]
          end.reject { |m| parent_method_names.include?(m[0]) }

          # For overridden methods, replace parent entries with own implementation
          result = inherited.map do |parent_entry|
            method_name = parent_entry[0]
            if @methods.key?(method_name)
              # Override: use child's implementation but keep same vtable index
              [method_name, @methods[method_name], @name]
            else
              parent_entry
            end
          end

          result + own
        end

        # Get vtable index for a method
        # @param method_name [Symbol] Method name
        # @param registry [Hash{Symbol => NativeClassType}] Registry of all native classes
        # @return [Integer, nil] Vtable index (0-based) or nil if method not in vtable
        def vtable_index(method_name, registry)
          methods = vtable_methods(registry)
          methods.index { |m| m[0] == method_name.to_sym }
        end

        # Get the vtable size (number of methods)
        def vtable_size(registry)
          vtable_methods(registry).size
        end

        def to_s
          field_strs = fields.map { |n, t| "@#{n}: #{t}" }.join(", ")
          method_strs = methods.keys.map(&:to_s).join(", ")
          base = superclass ? " < #{superclass}" : ""
          "NativeClass[#{name}#{base}]{#{field_strs}}[#{method_strs}]"
        end

        # Get field type by name (own fields only)
        def field_type(field_name)
          fields[field_name.to_sym]
        end

        # Get field index for struct layout (includes inherited fields)
        # @param field_name [Symbol, String] Field name
        # @param registry [Hash{Symbol => NativeClassType}] Registry of all native classes
        def field_index(field_name, registry = nil)
          all = all_fields(registry || {})
          all.keys.index(field_name.to_sym)
        end

        # Get total number of fields (including inherited)
        def field_count(registry = nil)
          all_fields(registry || {}).size
        end

        # Calculate byte size (assuming 8 bytes per field, including inherited)
        def byte_size(registry = nil)
          all_fields(registry || {}).size * 8
        end

        # Check if this is a value type (pass-by-value semantics)
        def is_value_type?
          @is_value_type == true
        end

        # Validate that this type can be used as a value type
        # Returns [valid, error_message]
        def valid_value_type?(registry = nil)
          reg = registry || @native_class_registry || {}

          # Check for VALUE fields (String, Array, Hash, Object)
          all = all_fields(reg)
          value_fields = all.select { |_, type| RUBY_OBJECT_TYPES.include?(type) || type.is_a?(Hash) }
          unless value_fields.empty?
            return [false, "Value type cannot have Ruby object fields: #{value_fields.keys.join(', ')}"]
          end

          # Check size limit (128 bytes max for efficient register passing)
          size = byte_size(reg)
          if size > 128
            return [false, "Value type too large (#{size} bytes > 128 bytes max)"]
          end

          # Check for superclass (value types cannot have inheritance for simplicity)
          if @superclass
            return [false, "Value types cannot have superclass"]
          end

          [true, nil]
        end

        # Get LLVM type tag for a field
        def llvm_field_type_tag(field_name, registry = nil)
          reg = registry || @native_class_registry || {}
          all = all_fields(reg)
          field_type = all[field_name.to_sym]
          case field_type
          when :Int64 then :i64
          when :Float64 then :double
          when :Bool then :i8
          when :String, :Object, :Array, :Hash then :value  # Ruby objects stored as VALUE
          when Hash
            # Reference to another NativeClass (stored as VALUE)
            :value
          else
            # Check if it's an embedded NativeClass
            if field_type.is_a?(Symbol) && reg.key?(field_type)
              :embedded_native_class
            else
              :value
            end
          end
        end

        # Check if a field is a NativeClass reference (not embedded)
        def native_class_reference?(field_name, registry = nil)
          all = all_fields(registry || @native_class_registry || {})
          field_type = all[field_name.to_sym]
          field_type.is_a?(Hash) && field_type.key?(:ref)
        end

        # Get the referenced NativeClass name for a reference field
        def referenced_class_name(field_name, registry = nil)
          all = all_fields(registry || @native_class_registry || {})
          field_type = all[field_name.to_sym]
          field_type.is_a?(Hash) ? field_type[:ref] : nil
        end

        # Check if this class has any Ruby object fields (need GC marking)
        def has_ruby_object_fields?(registry = nil)
          reg = registry || @native_class_registry || {}
          all_fields(reg).values.any? do |field_type|
            RUBY_OBJECT_TYPES.include?(field_type) || field_type.is_a?(Hash)
          end
        end

        # Get all Ruby object field names (for GC marking)
        def ruby_object_field_names(registry = nil)
          reg = registry || @native_class_registry || {}
          all_fields(reg).select do |_, field_type|
            RUBY_OBJECT_TYPES.include?(field_type) || field_type.is_a?(Hash)
          end.keys
        end

        # Wren-style method lookup: walk up superclass chain
        # @param method_name [Symbol] Method name to look up
        # @param registry [Hash{Symbol => NativeClassType}] Registry of all native classes
        # @return [NativeMethodType, nil] Method signature if found
        def lookup_method(method_name, registry)
          method_name = method_name.to_sym
          return @methods[method_name] if @methods.key?(method_name)
          return nil unless @superclass

          parent = registry[@superclass]
          parent&.lookup_method(method_name, registry)
        end

        # Find which class implements a method (for static dispatch)
        # @param method_name [Symbol] Method name
        # @param registry [Hash{Symbol => NativeClassType}] Registry of all native classes
        # @return [NativeClassType, nil] The class that implements the method
        def find_method_owner(method_name, registry)
          method_name = method_name.to_sym
          return self if @methods.key?(method_name)
          return nil unless @superclass

          parent = registry[@superclass]
          parent&.find_method_owner(method_name, registry)
        end

        # Get all fields including inherited ones (superclass fields come first)
        # @param registry [Hash{Symbol => NativeClassType}] Registry of all native classes
        # @return [Hash{Symbol => Symbol}] All fields in memory layout order
        def all_fields(registry)
          inherited = if @superclass
            parent = registry[@superclass]
            parent ? parent.all_fields(registry) : {}
          else
            {}
          end
          inherited.merge(@fields)
        end

        # Check if this class has any methods (own or inherited)
        def has_methods?(registry)
          return true unless @methods.empty?
          return false unless @superclass

          parent = registry[@superclass]
          parent&.has_methods?(registry) || false
        end

        # Check if a field type is an embedded NativeClass
        def embedded_native_class?(field_name, registry = nil)
          reg = registry || @native_class_registry || {}
          field_type = fields[field_name.to_sym]
          return false unless field_type.is_a?(Symbol)
          return false if ALLOWED_PRIMITIVE_TYPES.include?(field_type)
          reg.key?(field_type)
        end

        # Get the embedded NativeClassType for a field
        def embedded_class_type(field_name, registry = nil)
          reg = registry || @native_class_registry || {}
          field_type = fields[field_name.to_sym]
          return nil unless field_type.is_a?(Symbol)
          reg[field_type]
        end

        private

        def validate_fields!
          fields.each do |field_name, field_type|
            next if ALLOWED_PRIMITIVE_TYPES.include?(field_type)

            # Check if it's an embedded NativeClass type (validated later when registry is available)
            next if field_type.is_a?(Symbol)

            raise ArgumentError,
              "NativeClass field '#{field_name}' has invalid type #{field_type}. " \
              "Allowed types: #{ALLOWED_PRIMITIVE_TYPES.join(', ')} or another NativeClass"
          end
        end
      end

      # Method signature for NativeClass methods
      class NativeMethodType
        attr_reader :param_types, :return_type, :param_names

        # Allowed types for parameters and return values
        # - :Int64, :Float64 - primitive unboxed types
        # - Symbol (class name) - reference to another NativeClass
        # - :Self - the class itself (for return type)
        # - :Void - no return value (returns nil)

        # @param param_types [Array<Symbol>] Parameter types
        # @param return_type [Symbol] Return type
        # @param param_names [Array<Symbol>] Optional parameter names
        def initialize(param_types, return_type, param_names: [])
          @param_types = param_types
          @return_type = return_type
          @param_names = param_names
        end

        def ==(other)
          return false unless other.is_a?(NativeMethodType)
          param_types == other.param_types && return_type == other.return_type
        end

        def hash
          [param_types, return_type].hash
        end

        def to_s
          params = param_types.map(&:to_s).join(", ")
          "(#{params}) -> #{return_type}"
        end

        # Get arity (number of parameters, excluding self)
        def arity
          param_types.size
        end

        # Check if this method returns a value
        def returns_value?
          return_type != :Void
        end

        # Convert return type to internal type representation
        def return_type_as_internal
          case return_type
          when :Int64 then ClassInstance.new(:Integer)
          when :Float64 then ClassInstance.new(:Float)
          when :Void then NIL
          else ClassInstance.new(return_type)
          end
        end
      end

      # C function type - represents an external C function callable via @cfunc
      # Used for direct C function calls without rb_funcallv overhead
      # Example RBS annotation:
      #   # @cfunc "fast_sin" : (Float) -> Float
      #   def self.sin: (Float) -> Float
      class CFuncType
        attr_reader :c_func_name, :param_types, :return_type

        # Type mappings from RBS to C/LLVM types
        C_TYPE_MAP = {
          Float: :double,
          Integer: :int64,
          String: :ptr,
          Bool: :i1,
          void: :void
        }.freeze

        # @param c_func_name [String] The C function name to call
        # @param param_types [Array<Symbol>] Parameter types (:Float, :Integer, etc.)
        # @param return_type [Symbol] Return type
        def initialize(c_func_name, param_types, return_type)
          @c_func_name = c_func_name
          @param_types = param_types
          @return_type = return_type
        end

        def ==(other)
          return false unless other.is_a?(CFuncType)

          c_func_name == other.c_func_name &&
            param_types == other.param_types &&
            return_type == other.return_type
        end

        def hash
          [c_func_name, param_types, return_type].hash
        end

        def to_s
          "CFuncType(#{c_func_name}: (#{param_types.join(", ")}) -> #{return_type})"
        end

        def llvm_param_types
          param_types.map { |t| C_TYPE_MAP[t] || :value }
        end

        def llvm_return_type
          C_TYPE_MAP[return_type] || :value
        end
      end

      # Method signature for extern class methods
      # Used for both constructors (returning opaque pointer) and instance methods
      class ExternMethodType
        attr_reader :c_func_name, :param_types, :return_type, :is_constructor

        # Type mappings from RBS to C/LLVM types (same as CFuncType)
        C_TYPE_MAP = CFuncType::C_TYPE_MAP

        # @param c_func_name [String] The C function name to call
        # @param param_types [Array<Symbol>] Parameter types (:Float, :Integer, :String, :ptr, etc.)
        # @param return_type [Symbol] Return type (:ptr for constructor, or other types)
        # @param is_constructor [Boolean] True if this is a constructor method (self.xxx)
        def initialize(c_func_name, param_types, return_type, is_constructor: false)
          @c_func_name = c_func_name
          @param_types = param_types
          @return_type = return_type
          @is_constructor = is_constructor
        end

        def ==(other)
          return false unless other.is_a?(ExternMethodType)

          c_func_name == other.c_func_name &&
            param_types == other.param_types &&
            return_type == other.return_type &&
            is_constructor == other.is_constructor
        end

        def hash
          [c_func_name, param_types, return_type, is_constructor].hash
        end

        def to_s
          kind = is_constructor ? "constructor" : "method"
          "ExternMethod[#{kind}](#{c_func_name}: (#{param_types.join(", ")}) -> #{return_type})"
        end

        def llvm_param_types
          param_types.map { |t| C_TYPE_MAP[t] || :value }
        end

        def llvm_return_type
          C_TYPE_MAP[return_type] || :value
        end

        # Convert return type to internal type representation
        def return_type_as_internal
          case return_type
          when :ptr then UNTYPED  # Opaque pointer, handled specially
          when :Float then FLOAT
          when :Integer then INTEGER
          when :String then STRING
          when :Bool then BOOL
          when :void then NIL
          else UNTYPED
          end
        end
      end

      # ExternClass type - wraps pointer to external C struct
      # Marked with @native extern annotation in RBS
      # Only holds void* pointer, no field definitions
      # Requires @ffi annotation for library linking
      #
      # Example:
      #   # @ffi "libsqlite3"
      #   # @native extern
      #   class SQLiteDB
      #     def self.open: (String path) -> SQLiteDB
      #     def execute: (String sql) -> Array
      #     def close: () -> void
      #   end
      class ExternClassType < Type
        attr_reader :name, :ffi_library, :methods

        # @param name [Symbol] Class name
        # @param ffi_library [String] Library name to link (e.g., "libsqlite3")
        # @param methods [Hash{Symbol => ExternMethodType}] Method name -> signature
        def initialize(name, ffi_library, methods = {})
          @name = name.to_sym
          @ffi_library = ffi_library
          @methods = methods
        end

        def ==(other)
          return false unless other.is_a?(ExternClassType)
          name == other.name && ffi_library == other.ffi_library
        end

        def hash
          [name, ffi_library].hash
        end

        def to_s
          "ExternClass[#{name} from #{ffi_library}]"
        end

        # Look up a method by name
        def lookup_method(method_name)
          @methods[method_name.to_sym]
        end

        # Check if a method is a constructor (singleton method that returns Self)
        def constructor?(method_name)
          method_sig = @methods[method_name.to_sym]
          method_sig&.is_constructor || false
        end
      end

      # SIMDClass type - fixed-size vector of Float64 values
      # Marked with @simd annotation in RBS
      # Supports element-wise arithmetic via LLVM vector operations
      #
      # Example:
      #   # @simd
      #   class Vector4
      #     @x: Float
      #     @y: Float
      #     @z: Float
      #     @w: Float
      #
      #     def add: (Vector4) -> Vector4
      #     def dot: (Vector4) -> Float
      #   end
      class SIMDClassType < Type
        attr_reader :name, :field_names, :methods, :vector_width

        # Allowed SIMD widths (must be 2, 3, 4, 8, or 16)
        ALLOWED_WIDTHS = [2, 3, 4, 8, 16].freeze

        # @param name [Symbol] Class name
        # @param field_names [Array<Symbol>] Field names in order (all Float64)
        # @param methods [Hash{Symbol => NativeMethodType}] Method name -> signature
        def initialize(name, field_names, methods = {})
          @name = name.to_sym
          @field_names = field_names.map(&:to_sym)
          @methods = methods
          @vector_width = field_names.size
          validate!
        end

        def ==(other)
          return false unless other.is_a?(SIMDClassType)
          name == other.name && field_names == other.field_names
        end

        def hash
          [name, field_names].hash
        end

        def to_s
          "SIMDClass[#{name}]<#{vector_width} x double>"
        end

        # Get field index by name
        def field_index(field_name)
          @field_names.index(field_name.to_sym)
        end

        # Check if a name is a field
        def field?(field_name)
          @field_names.include?(field_name.to_sym)
        end

        # Get LLVM vector width (padded to power of 2)
        # Vector3 uses <4 x double> internally
        def llvm_vector_width
          return 2 if @vector_width <= 2
          return 4 if @vector_width <= 4
          return 8 if @vector_width <= 8
          16
        end

        # Look up a method by name
        def lookup_method(method_name)
          @methods[method_name.to_sym]
        end

        private

        def validate!
          unless ALLOWED_WIDTHS.include?(@vector_width)
            raise ArgumentError,
              "SIMDClass '#{@name}' must have #{ALLOWED_WIDTHS.join('/')} Float fields, got #{@vector_width}"
          end
        end
      end

      # NativeModule type - module with methods but no instance state
      # Marked with @native annotation in RBS
      # Can be included in classes to mix in methods
      class NativeModuleType < Type
        attr_reader :name, :methods

        # @param name [Symbol] Module name
        # @param methods [Hash{Symbol => NativeMethodType}] Method name -> signature
        def initialize(name, methods = {})
          @name = name.to_sym
          @methods = methods
        end

        # Look up a method by name
        def lookup_method(method_name)
          @methods[method_name.to_sym]
        end

        def ==(other)
          return false unless other.is_a?(NativeModuleType)
          name == other.name
        end

        def hash
          name.hash
        end

        def to_s
          "NativeModule(#{name})"
        end
      end

      # Tuple type [A, B, C]
      class Tuple < Type
        attr_reader :element_types

        def initialize(element_types)
          @element_types = element_types
        end

        def ==(other)
          return false unless other.is_a?(Tuple)
          element_types == other.element_types
        end

        def hash
          element_types.hash
        end

        def to_s
          "[#{element_types.map(&:to_s).join(", ")}]"
        end
      end

      # Literal type (specific value)
      class Literal < Type
        attr_reader :value

        def initialize(value)
          @value = value
        end

        def ==(other)
          return false unless other.is_a?(Literal)
          value == other.value
        end

        def hash
          value.hash
        end

        def to_s
          value.inspect
        end

        def subtype_of?(other)
          return true if super
          return false unless other.is_a?(ClassInstance)

          case value
          when Integer then other.name == :Integer
          when Float then other.name == :Float
          when String then other.name == :String
          when Symbol then other.name == :Symbol
          when true, false then other.name == :TrueClass || other.name == :FalseClass
          else false
          end
        end
      end

      # Helper methods
      module_function

      UNTYPED = Untyped.new.freeze
      NIL = NilType.new.freeze
      BOOL = BoolType.new.freeze
      BOTTOM = Bottom.new.freeze

      INTEGER = ClassInstance.new(:Integer).freeze
      FLOAT = ClassInstance.new(:Float).freeze
      STRING = ClassInstance.new(:String).freeze
      SYMBOL = ClassInstance.new(:Symbol).freeze
      REGEXP = ClassInstance.new(:Regexp).freeze
      TRUE_CLASS = ClassInstance.new(:TrueClass).freeze
      FALSE_CLASS = ClassInstance.new(:FalseClass).freeze
      FIBER = ClassInstance.new(:Fiber).freeze
      THREAD = ClassInstance.new(:Thread).freeze
      MUTEX = ClassInstance.new(:Mutex).freeze
      QUEUE = ClassInstance.new(:Queue).freeze
      CONDITION_VARIABLE = ClassInstance.new(:ConditionVariable).freeze
      SIZED_QUEUE = ClassInstance.new(:SizedQueue).freeze
      RACTOR = ClassInstance.new(:Ractor).freeze
      RACTOR_PORT = ClassInstance.new(:"Ractor::Port").freeze

      # Additional standard library types
      TIME = ClassInstance.new(:Time).freeze
      MATCH_DATA = ClassInstance.new(:MatchData).freeze
      RANGE = ClassInstance.new(:Range).freeze

      # Native buffer types for efficient I/O
      BYTEBUFFER = ByteBufferType.new.freeze
      BYTESLICE = ByteSliceType.new.freeze
      STRINGBUFFER = StringBufferType.new.freeze
      NATIVESTRING = NativeStringType.new.freeze

      # Generic slice types
      SLICE_INT64 = SliceType.new(:Int64).freeze
      SLICE_FLOAT64 = SliceType.new(:Float64).freeze

      def array(element_type)
        ClassInstance.new(:Array, [element_type])
      end

      def hash_type(key_type, value_type)
        ClassInstance.new(:Hash, [key_type, value_type])
      end

      def union(*types)
        flat_types = types.flat_map { |t| t.is_a?(Union) ? t.types : [t] }
        flat_types = flat_types.reject { |t| t.is_a?(Bottom) }
        return BOTTOM if flat_types.empty?
        return flat_types.first if flat_types.size == 1
        Union.new(flat_types)
      end

      def optional(type)
        union(type, NIL)
      end

      def native_array(element_type)
        NativeArrayType.new(element_type)
      end

      # Predefined NativeArray types
      NATIVE_ARRAY_INT64 = NativeArrayType.new(:Int64).freeze
      NATIVE_ARRAY_FLOAT64 = NativeArrayType.new(:Float64).freeze
    end
  end
end

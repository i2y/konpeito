# frozen_string_literal: true

require_relative "types"

module Konpeito
  module TypeChecker
    # Type variable for Hindley-Milner inference
    class TypeVar
      @@counter = 0

      attr_reader :id
      attr_accessor :instance  # Bound type after unification

      def initialize(name = nil)
        @id = @@counter += 1
        @name = name || "τ#{@id}"
        @instance = nil
      end

      def to_s
        if @instance
          @instance.to_s
        else
          @name
        end
      end

      def inspect
        "#<TypeVar #{@name}#{@instance ? " = #{@instance}" : ""}>"
      end

      def prune
        # Follow the chain of instantiated type variables
        if @instance.is_a?(TypeVar)
          @instance = @instance.prune
        end
        @instance || self
      end

      def ==(other)
        other.is_a?(TypeVar) && @id == other.id
      end

      def hash
        @id.hash
      end

      alias eql? ==
    end

    # Function type for HM inference
    class FunctionType
      attr_reader :param_types, :return_type, :rest_param_type

      def initialize(param_types, return_type, rest_param_type: nil)
        @param_types = param_types
        @return_type = return_type
        @rest_param_type = rest_param_type  # TypeVar for *args element type (nil if no rest)
      end

      def to_s
        params = @param_types.map(&:to_s).join(", ")
        params += ", *#{@rest_param_type}" if @rest_param_type
        "(#{params}) -> #{@return_type}"
      end

      def ==(other)
        other.is_a?(FunctionType) &&
          @param_types == other.param_types &&
          @return_type == other.return_type &&
          @rest_param_type == other.rest_param_type
      end
    end

    # Unification error
    class UnificationError < Error
      attr_reader :type1, :type2, :node, :context

      def initialize(type1, type2, node: nil, context: nil)
        @type1 = type1
        @type2 = type2
        @node = node  # Prism node where error occurred
        @context = context  # Additional context (e.g., "in argument 1 of method 'foo'")
        super("Cannot unify #{type1} with #{type2}")
      end
    end

    # Unification algorithm
    class Unifier
      def initialize
        @substitution = {}
      end

      # Unify two types, updating substitutions
      #
      # nil compatibility: In Ruby, all reference types are implicitly nullable.
      # Unlike Kotlin (which distinguishes T vs T?), Ruby has no non-nullable types.
      # We treat nil as a subtype of every type — unification succeeds, but the
      # concrete type is always preserved (nil never overwrites type information).
      def unify(t1, t2)
        t1 = prune(t1)
        t2 = prune(t2)

        if t1.is_a?(TypeVar)
          if t1 != t2
            if occurs_in?(t1, t2)
              raise UnificationError.new(t1, t2)
            end
            # If TypeVar is already bound to a ClassInstance and t2 is also ClassInstance,
            # check for subtype/LUB before rebinding
            if t1.instance.is_a?(Types::ClassInstance) && t2.is_a?(Types::ClassInstance) && t1.instance.name != t2.name
              existing = t1.instance
              if numeric_widening?(existing, t2)
                # Integer → Float widening (Java/Kotlin widening primitive conversion)
                t1.instance = t2
              elsif numeric_widening?(t2, existing)
                # Float already bound, Integer is compatible — keep Float
              elsif t2.subtype_of?(existing)
                # New type is subtype of existing — keep existing (supertype)
              elsif existing.subtype_of?(t2)
                # Existing is subtype of new — widen to new
                t1.instance = t2
              else
                lub = Types::ClassInstance.find_lub(existing, t2)
                if lub
                  t1.instance = lub
                else
                  raise UnificationError.new(existing, t2)
                end
              end
            else
              t1.instance = t2
            end
          end
        elsif t2.is_a?(TypeVar)
          unify(t2, t1)
        elsif t1.is_a?(FunctionType) && t2.is_a?(FunctionType)
          if t1.param_types.size != t2.param_types.size
            raise UnificationError.new(t1, t2)
          end
          t1.param_types.zip(t2.param_types).each do |p1, p2|
            unify(p1, p2)
          end
          if t1.rest_param_type && t2.rest_param_type
            unify(t1.rest_param_type, t2.rest_param_type)
          end
          unify(t1.return_type, t2.return_type)
        elsif t1.is_a?(Types::ClassInstance) && t2.is_a?(Types::ClassInstance)
          if t1.name != t2.name
            # TrueClass/FalseClass are boolean-compatible
            if boolean_compatible?(t1, t2)
              # Both are boolean types — compatible
            # Integer → Float widening (Java/Kotlin widening primitive conversion)
            elsif numeric_widening?(t1, t2) || numeric_widening?(t2, t1)
              # Integer is safely widened to Float — compatible
            # Check subtype relationship before failing
            elsif t1.subtype_of?(t2)
              # t1 is a subtype of t2 — compatible (keep supertype)
            elsif t2.subtype_of?(t1)
              # t2 is a subtype of t1 — compatible (keep supertype)
            else
              # Try to find LUB (Least Upper Bound)
              lub = Types::ClassInstance.find_lub(t1, t2)
              if lub && lub.name != :Object
                # Found a meaningful common ancestor
              else
                raise UnificationError.new(t1, t2)
              end
            end
          else
            # Same class name — unify type arguments if any
            t1.type_args.zip(t2.type_args).each do |a1, a2|
              unify(a1, a2)
            end
          end
        elsif t1 == t2
          # Same type, nothing to do
        elsif t1 == Types::UNTYPED || t2 == Types::UNTYPED
          # UNTYPED unifies with anything (escape hatch)
        elsif t1 == Types::NIL || t2 == Types::NIL
          # nil is a subtype of every type in Ruby (implicit nullable).
          # Compatible, but no type information is lost — the concrete side is preserved.
        elsif boolean_compatible?(t1, t2)
          # TrueClass, FalseClass, and Bool are all boolean-compatible.
          # Ruby has separate TrueClass/FalseClass but they're used interchangeably.
        elsif singleton_value_compatible?(t1, t2)
          # ClassSingleton (value constant like EXPANDING) is compatible with its base type.
          # e.g., singleton(EXPANDING) ↔ Integer when EXPANDING = 2
        elsif literal_compatible?(t1, t2)
          # Literals are subtypes of their base type (e.g., Literal(1) <: Integer, Literal("x") <: String)
          # Unions of same-type literals are also compatible (e.g., -1 | 0 | 1 <: Integer)
        elsif t1.is_a?(Types::Union) || t2.is_a?(Types::Union)
          # Union type compatibility: a concrete type T unifies with Union[T, ...]
          # if T matches any member of the union. This handles:
          # - RBS optional params (String? = String | nil) with String args
          # - RBS union return types (Array[U] | U) with concrete Array[T] block results
          union_compatible?(t1, t2)
        else
          raise UnificationError.new(t1, t2)
        end
      end

      # Check if both types are boolean-compatible (TrueClass, FalseClass, Bool)
      def boolean_compatible?(t1, t2)
        bool_types = Set[:TrueClass, :FalseClass]
        (t1.is_a?(Types::ClassInstance) && bool_types.include?(t1.name) &&
          t2.is_a?(Types::ClassInstance) && bool_types.include?(t2.name)) ||
        (t1 == Types::BOOL && t2.is_a?(Types::ClassInstance) && bool_types.include?(t2.name)) ||
        (t2 == Types::BOOL && t1.is_a?(Types::ClassInstance) && bool_types.include?(t1.name))
      end

      # Check if a ClassSingleton (value constant) is compatible with a concrete type.
      # Value constants (EXPANDING = 2) produce ClassSingleton but should unify with Integer.
      def singleton_value_compatible?(t1, t2)
        (t1.is_a?(Types::ClassSingleton) && t2.is_a?(Types::ClassInstance)) ||
        (t2.is_a?(Types::ClassSingleton) && t1.is_a?(Types::ClassInstance))
      end

      # Check if a literal type (or union of literals) is compatible with its base class type.
      # e.g., Literal(1) <: Integer, Literal("hello") <: String, Literal(1.0) <: Float
      #        Union(Literal(-1), Literal(0), Literal(1)) <: Integer
      def literal_compatible?(t1, t2)
        (literal_subtype_of_class?(t1, t2)) || (literal_subtype_of_class?(t2, t1))
      end

      def literal_subtype_of_class?(literal_side, class_side)
        return false unless class_side.is_a?(Types::ClassInstance)

        if literal_side.is_a?(Types::Literal)
          literal_base_type_name(literal_side.value) == class_side.name
        elsif literal_side.is_a?(Types::Union)
          literal_side.types.all? do |sub|
            sub.is_a?(Types::Literal) && literal_base_type_name(sub.value) == class_side.name
          end
        else
          false
        end
      end

      # Map a Ruby literal value to its base type name
      def literal_base_type_name(value)
        case value
        when Integer then :Integer
        when Float then :Float
        when String then :String
        when Symbol then :Symbol
        when true, false then :Bool
        end
      end

      # Check union type compatibility.
      # A concrete type T is compatible with Union[T, ...] if T matches any member.
      # TypeVars within union members are unified when a match is found.
      # If both sides are unions, check if all members of one are covered by the other.
      def union_compatible?(t1, t2)
        if t1.is_a?(Types::Union) && t2.is_a?(Types::Union)
          # Both are unions — compatible if they share at least one member type
          # or one is a subtype of the other
          return if t1.subtype_of?(t2) || t2.subtype_of?(t1)

          raise UnificationError.new(t1, t2)
        end

        # One is a union, the other is concrete
        union, concrete = t1.is_a?(Types::Union) ? [t1, t2] : [t2, t1]

        # Try to unify the concrete type with each union member.
        # If any member succeeds, the union is compatible.
        union.types.each do |member|
          begin
            unify(concrete, member)
            return  # Success — found a matching member
          rescue UnificationError
            # Try next member
          end
        end

        # No union member matched — raise error
        raise UnificationError.new(t1, t2)
      end

      # Check if `from` can be widened to `to` (Java/Kotlin-style widening primitive conversion).
      # Integer → Float is safe (no precision loss for typical values).
      # Float → Integer is NOT supported (requires explicit conversion).
      def numeric_widening?(from, to)
        from.is_a?(Types::ClassInstance) && to.is_a?(Types::ClassInstance) &&
          from.name == :Integer && to.name == :Float
      end

      # Prune: follow type variable chain
      def prune(t)
        if t.is_a?(TypeVar) && t.instance
          t.instance = prune(t.instance)
          t.instance
        else
          t
        end
      end

      # Occurs check: prevent infinite types
      def occurs_in?(tvar, type)
        type = prune(type)
        return true if tvar == type

        if type.is_a?(FunctionType)
          type.param_types.any? { |p| occurs_in?(tvar, p) } ||
            (type.rest_param_type && occurs_in?(tvar, type.rest_param_type)) ||
            occurs_in?(tvar, type.return_type)
        elsif type.is_a?(Types::ClassInstance)
          type.type_args.any? { |a| occurs_in?(tvar, a) }
        else
          false
        end
      end

      # Apply substitution to get final type
      def apply(type)
        type = prune(type)

        case type
        when TypeVar
          type.instance ? apply(type.instance) : type
        when FunctionType
          FunctionType.new(
            type.param_types.map { |p| apply(p) },
            apply(type.return_type),
            rest_param_type: type.rest_param_type ? apply(type.rest_param_type) : nil
          )
        when Types::ClassInstance
          if type.type_args.empty?
            type
          else
            Types::ClassInstance.new(
              type.name,
              type.type_args.map { |a| apply(a) }
            )
          end
        else
          type
        end
      end
    end

    # Type scheme (polymorphic type with quantified variables)
    class TypeScheme
      attr_reader :type_vars, :type

      def initialize(type_vars, type)
        @type_vars = type_vars
        @type = type
      end

      # Instantiate: replace bound variables with fresh ones
      def instantiate
        mapping = {}
        @type_vars.each do |tv|
          mapping[tv.id] = TypeVar.new
        end
        substitute(@type, mapping)
      end

      private

      def substitute(type, mapping)
        case type
        when TypeVar
          if type.instance
            substitute(type.instance, mapping)
          elsif mapping[type.id]
            mapping[type.id]
          else
            type
          end
        when FunctionType
          FunctionType.new(
            type.param_types.map { |p| substitute(p, mapping) },
            substitute(type.return_type, mapping),
            rest_param_type: type.rest_param_type ? substitute(type.rest_param_type, mapping) : nil
          )
        when Types::ClassInstance
          if type.type_args.empty?
            type
          else
            Types::ClassInstance.new(
              type.name,
              type.type_args.map { |a| substitute(a, mapping) }
            )
          end
        else
          type
        end
      end
    end
  end
end

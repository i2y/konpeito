# frozen_string_literal: true

module Konpeito
  module Codegen
    # Mapping of Ruby built-in methods to their CRuby C API functions
    # This enables direct C function calls instead of rb_funcallv dispatch
    #
    # IMPORTANT: Only include functions that are actually EXPORTED from libruby.
    # Many internal Ruby methods (like rb_str_upcase) are static and not callable.
    # Check with: nm -gU $(ruby -e 'puts RbConfig::CONFIG["libdir"]')/libruby.*.dylib | grep rb_str
    #
    # Calling conventions:
    # - :simple - VALUE func(VALUE recv) or VALUE func(VALUE recv, VALUE arg1, ...)
    # - :block_iterator - uses rb_block_call with block callback
    #
    BUILTIN_METHODS = {
      Integer: {
        # Block iterators - use rb_block_call
        times: { arity: 0, return_type: :Integer, conv: :block_iterator },
        upto: { arity: 1, return_type: :Integer, conv: :block_iterator },
        downto: { arity: 1, return_type: :Integer, conv: :block_iterator },
      },

      String: {
        # String query methods
        length: { c_func: "rb_str_length", arity: 0, return_type: :Integer, conv: :simple },
        size: { c_func: "rb_str_length", arity: 0, return_type: :Integer, conv: :simple },

        # String operations - these are EXPORTED
        :+ => { c_func: "rb_str_plus", arity: 1, return_type: :String, conv: :simple },
        :<< => { c_func: "rb_str_concat", arity: 1, return_type: :String, conv: :simple },
        concat: { c_func: "rb_str_concat", arity: 1, return_type: :String, conv: :simple },

        # String comparison - exported
        :<=> => { c_func: "rb_str_cmp", arity: 1, return_type: :Integer, conv: :simple },
        :== => { c_func: "rb_str_equal", arity: 1, return_type: :Bool, conv: :simple },

        # String conversion - exported
        to_sym: { c_func: "rb_str_intern", arity: 0, return_type: :Symbol, conv: :simple },
        intern: { c_func: "rb_str_intern", arity: 0, return_type: :Symbol, conv: :simple },

        # String duplication - exported
        dup: { c_func: "rb_str_dup", arity: 0, return_type: :String, conv: :simple },

        # String hash - exported (useful for Hash key optimization)
        hash: { c_func: "rb_str_hash", arity: 0, return_type: :Integer, conv: :simple },
      },

      Array: {
        # Array query methods - rb_ary_length not directly exported, use RARRAY_LEN macro
        # length: { c_func: "rb_ary_length", arity: 0, return_type: :Integer, conv: :simple },

        # Array access - exported
        :[] => { c_func: "rb_ary_entry", arity: 1, return_type: :Any, conv: :ary_entry },
        # Array#[]= uses rb_ary_store (special handling in llvm_generator)
        :[]= => { c_func: "rb_ary_store", arity: 2, return_type: :Any, conv: :ary_store },

        # Array modification - exported with simple signatures
        push: { c_func: "rb_ary_push", arity: 1, return_type: :Array, conv: :simple },
        :<<  => { c_func: "rb_ary_push", arity: 1, return_type: :Array, conv: :simple },
        pop: { c_func: "rb_ary_pop", arity: 0, return_type: :Any, conv: :simple },
        shift: { c_func: "rb_ary_shift", arity: 0, return_type: :Any, conv: :simple },
        clear: { c_func: "rb_ary_clear", arity: 0, return_type: :Array, conv: :simple },
        # Array#delete_at uses long index (special handling in llvm_generator)
        delete_at: { c_func: "rb_ary_delete_at", arity: 1, return_type: :Any, conv: :ary_delete_at },
        # Note: unshift/prepend/delete use rb_funcallv fallback (args need VALUE boxing)

        # Array operations - exported
        :+ => { c_func: "rb_ary_plus", arity: 1, return_type: :Array, conv: :simple },
        concat: { c_func: "rb_ary_concat", arity: 1, return_type: :Array, conv: :simple },

        # Array transformation - exported
        reverse: { c_func: "rb_ary_reverse", arity: 0, return_type: :Array, conv: :simple },
        sort: { c_func: "rb_ary_sort", arity: 0, return_type: :Array, conv: :simple },

        # Array query with args - exported
        include?: { c_func: "rb_ary_includes", arity: 1, return_type: :Bool, conv: :simple },

        # Block iterators - use rb_block_call
        each: { arity: 0, return_type: :Array, conv: :block_iterator },
        map: { arity: 0, return_type: :Array, conv: :block_iterator },
        collect: { arity: 0, return_type: :Array, conv: :block_iterator },
        select: { arity: 0, return_type: :Array, conv: :block_iterator },
        filter: { arity: 0, return_type: :Array, conv: :block_iterator },  # alias for select
        reject: { arity: 0, return_type: :Array, conv: :block_iterator },
        each_with_index: { arity: 0, return_type: :Array, conv: :block_iterator },

        # Enumerable methods
        reduce: { arity: -1, return_type: :Any, conv: :block_iterator },  # arity -1 = optional args
        inject: { arity: -1, return_type: :Any, conv: :block_iterator },  # alias for reduce
        find: { arity: 0, return_type: :Any, conv: :block_iterator },
        detect: { arity: 0, return_type: :Any, conv: :block_iterator },   # alias for find
        find_all: { arity: 0, return_type: :Array, conv: :block_iterator },  # alias for select
        any?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        all?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        none?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        one?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        count: { arity: -1, return_type: :Integer, conv: :block_iterator },  # optional block
        min_by: { arity: 0, return_type: :Any, conv: :block_iterator },
        max_by: { arity: 0, return_type: :Any, conv: :block_iterator },
        sort_by: { arity: 0, return_type: :Array, conv: :block_iterator },
        find_index: { arity: -1, return_type: :Any, conv: :block_iterator },
        first: { arity: -1, return_type: :Any, conv: :block_iterator },
        take_while: { arity: 0, return_type: :Array, conv: :block_iterator },
        drop_while: { arity: 0, return_type: :Array, conv: :block_iterator },
        partition: { arity: 0, return_type: :Array, conv: :block_iterator },
        group_by: { arity: 0, return_type: :Hash, conv: :block_iterator },
        flat_map: { arity: 0, return_type: :Array, conv: :block_iterator },
        collect_concat: { arity: 0, return_type: :Array, conv: :block_iterator },  # alias for flat_map
      },

      Hash: {
        # Hash access - rb_hash_aref is exported
        :[] => { c_func: "rb_hash_aref", arity: 1, return_type: :Any, conv: :simple },
        :[]= => { c_func: "rb_hash_aset", arity: 2, return_type: :Any, conv: :simple },

        # Hash modification - exported
        clear: { c_func: "rb_hash_clear", arity: 0, return_type: :Hash, conv: :simple },
        delete: { c_func: "rb_hash_delete", arity: 1, return_type: :Any, conv: :simple },

        # Hash block iterators with 2-argument blocks (|k, v|)
        # Uses rb_block_call - CRuby passes key/value through argv for Hash#each
        each: { arity: 0, return_type: :Hash, conv: :block_iterator },
        each_pair: { arity: 0, return_type: :Hash, conv: :block_iterator },
        map: { arity: 0, return_type: :Array, conv: :block_iterator },
        collect: { arity: 0, return_type: :Array, conv: :block_iterator },
        select: { arity: 0, return_type: :Hash, conv: :block_iterator },
        filter: { arity: 0, return_type: :Hash, conv: :block_iterator },
        reject: { arity: 0, return_type: :Hash, conv: :block_iterator },
        any?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        all?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        none?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        each_with_object: { arity: 1, return_type: :Any, conv: :block_iterator },
      },

      Symbol: {
        # Symbol methods
        to_s: { c_func: "rb_sym2str", arity: 0, return_type: :String, conv: :simple },
        id2name: { c_func: "rb_sym2str", arity: 0, return_type: :String, conv: :simple },
        name: { c_func: "rb_sym2str", arity: 0, return_type: :String, conv: :simple },
      },

      Object: {
        # Object identity and comparison
        :== => { c_func: "rb_obj_equal", arity: 1, return_type: :Bool, conv: :simple },
        :=== => { c_func: "rb_equal", arity: 1, return_type: :Bool, conv: :simple },

        # Object type checking
        is_a?: { c_func: "rb_obj_is_kind_of", arity: 1, return_type: :Bool, conv: :simple },
        kind_of?: { c_func: "rb_obj_is_kind_of", arity: 1, return_type: :Bool, conv: :simple },
        instance_of?: { c_func: "rb_obj_is_instance_of", arity: 1, return_type: :Bool, conv: :simple },

        # Object info - exported
        class: { c_func: "rb_obj_class", arity: 0, return_type: :Class, conv: :simple },
        object_id: { c_func: "rb_obj_id", arity: 0, return_type: :Integer, conv: :simple },

        # Object duplication - exported
        dup: { c_func: "rb_obj_dup", arity: 0, return_type: :Any, conv: :simple },
        freeze: { c_func: "rb_obj_freeze", arity: 0, return_type: :Any, conv: :simple },
      },

      Range: {
        # Block iterators
        each: { arity: 0, return_type: :Range, conv: :block_iterator },
        # Range enumerable methods
        map: { arity: 0, return_type: :Array, conv: :block_iterator },
        collect: { arity: 0, return_type: :Array, conv: :block_iterator },
        select: { arity: 0, return_type: :Array, conv: :block_iterator },
        filter: { arity: 0, return_type: :Array, conv: :block_iterator },
        reject: { arity: 0, return_type: :Array, conv: :block_iterator },
        reduce: { arity: -1, return_type: :Any, conv: :block_iterator },
        inject: { arity: -1, return_type: :Any, conv: :block_iterator },
        find: { arity: 0, return_type: :Any, conv: :block_iterator },
        detect: { arity: 0, return_type: :Any, conv: :block_iterator },
        any?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        all?: { arity: 0, return_type: :Bool, conv: :block_iterator },
        none?: { arity: 0, return_type: :Bool, conv: :block_iterator },
      },

      Float: {
        # Float comparison
        :<=> => { c_func: "rb_float_cmp", arity: 1, return_type: :Integer, conv: :simple },

        # Float conversion
        to_i: { c_func: "rb_num2long", arity: 0, return_type: :Integer, conv: :simple },
        to_int: { c_func: "rb_num2long", arity: 0, return_type: :Integer, conv: :simple },
        floor: { c_func: "rb_float_floor", arity: 0, return_type: :Integer, conv: :simple },
        ceil: { c_func: "rb_float_ceil", arity: 0, return_type: :Integer, conv: :simple },
        round: { c_func: "rb_float_round", arity: 0, return_type: :Integer, conv: :simple },
        truncate: { c_func: "rb_float_truncate", arity: 0, return_type: :Integer, conv: :simple },

        # Float query
        nan?: { c_func: "rb_float_nan_p", arity: 0, return_type: :Bool, conv: :simple },
        infinite?: { c_func: "rb_float_infinite_p", arity: 0, return_type: :Any, conv: :simple },
        finite?: { c_func: "rb_float_finite_p", arity: 0, return_type: :Bool, conv: :simple },
      },

      NilClass: {
        nil?: { c_func: "rb_true", arity: 0, return_type: :Bool, conv: :simple },
        to_s: { c_func: "rb_nil_to_s", arity: 0, return_type: :String, conv: :simple },
        to_a: { c_func: "rb_ary_new", arity: 0, return_type: :Array, conv: :simple },
        to_h: { c_func: "rb_hash_new", arity: 0, return_type: :Hash, conv: :simple },
      },

      TrueClass: {
        to_s: { c_func: "rb_true_to_s", arity: 0, return_type: :String, conv: :simple },
      },

      FalseClass: {
        to_s: { c_func: "rb_false_to_s", arity: 0, return_type: :String, conv: :simple },
      },
    }.freeze

    # Helper method to look up a builtin method
    def self.lookup(class_name, method_name)
      BUILTIN_METHODS.dig(class_name.to_sym, method_name.to_sym)
    end

    # Get all classes with builtin methods
    def self.builtin_classes
      BUILTIN_METHODS.keys
    end

    # Get all methods for a class
    def self.methods_for(class_name)
      BUILTIN_METHODS[class_name.to_sym] || {}
    end
  end
end

# frozen_string_literal: true

module Konpeito
  module AST
    # Base visitor class for traversing Prism AST nodes
    # Subclass and override visit_* methods to handle specific node types
    class Visitor
      def visit(node)
        return unless node

        method_name = :"visit_#{node_type(node)}"
        if respond_to?(method_name, true)
          send(method_name, node)
        else
          visit_default(node)
        end
      end

      def visit_all(nodes)
        nodes.each { |node| visit(node) }
      end

      private

      def visit_default(node)
        visit_children(node)
      end

      def visit_children(node)
        node.compact_child_nodes.each { |child| visit(child) }
      end

      def node_type(node)
        # Convert Prism::FooNode to :foo
        node.class.name.split("::").last.sub(/Node$/, "").gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      # Override these methods in subclasses to handle specific node types
      # Example method signatures:

      # def visit_program(node); end
      # def visit_statements(node); end
      # def visit_def(node); end
      # def visit_class(node); end
      # def visit_module(node); end
      # def visit_if(node); end
      # def visit_unless(node); end
      # def visit_while(node); end
      # def visit_until(node); end
      # def visit_for(node); end
      # def visit_case(node); end
      # def visit_call(node); end
      # def visit_local_variable_read(node); end
      # def visit_local_variable_write(node); end
      # def visit_instance_variable_read(node); end
      # def visit_instance_variable_write(node); end
      # def visit_class_variable_read(node); end
      # def visit_class_variable_write(node); end
      # def visit_constant_read(node); end
      # def visit_constant_write(node); end
      # def visit_integer(node); end
      # def visit_float(node); end
      # def visit_string(node); end
      # def visit_symbol(node); end
      # def visit_array(node); end
      # def visit_hash(node); end
      # def visit_block(node); end
      # def visit_lambda(node); end
      # def visit_begin(node); end
      # def visit_rescue(node); end
      # def visit_ensure(node); end
      # def visit_return(node); end
      # def visit_break(node); end
      # def visit_next(node); end
      # def visit_yield(node); end
    end
  end
end

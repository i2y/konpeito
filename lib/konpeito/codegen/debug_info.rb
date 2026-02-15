# frozen_string_literal: true

require "ffi"

module Konpeito
  module Codegen
    # FFI bindings for LLVM Debug Info C API
    module DebugInfoFFI
      extend FFI::Library

      # Load LLVM library
      begin
        ffi_lib(Konpeito::Platform.find_llvm_lib || "LLVM-20")
      rescue LoadError
        ffi_lib "LLVM-20"
      end

      # DWARF source language enum
      DWARF_SOURCE_LANGUAGE_RUBY = 56  # LLVMDWARFSourceLanguageRuby

      # DI Flags
      DI_FLAG_ZERO = 0

      # DIBuilder functions
      attach_function :LLVMCreateDIBuilder, [:pointer], :pointer
      attach_function :LLVMDisposeDIBuilder, [:pointer], :void
      attach_function :LLVMDIBuilderFinalize, [:pointer], :void

      # Create compile unit
      attach_function :LLVMDIBuilderCreateCompileUnit, [
        :pointer,  # Builder
        :uint,     # Language
        :pointer,  # FileRef
        :string,   # Producer
        :size_t,   # ProducerLen
        :int,      # isOptimized
        :string,   # Flags
        :size_t,   # FlagsLen
        :uint,     # RuntimeVer
        :string,   # SplitName
        :size_t,   # SplitNameLen
        :uint,     # Kind (DWARFEmissionKind)
        :uint,     # DWOId
        :int,      # SplitDebugInlining
        :int,      # DebugInfoForProfiling
        :string,   # SysRoot
        :size_t,   # SysRootLen
        :string,   # SDK
        :size_t    # SDKLen
      ], :pointer

      # Create file
      attach_function :LLVMDIBuilderCreateFile, [
        :pointer,  # Builder
        :string,   # Filename
        :size_t,   # FilenameLen
        :string,   # Directory
        :size_t    # DirectoryLen
      ], :pointer

      # Create function (subprogram)
      attach_function :LLVMDIBuilderCreateFunction, [
        :pointer,  # Builder
        :pointer,  # Scope
        :string,   # Name
        :size_t,   # NameLen
        :string,   # LinkageName
        :size_t,   # LinkageNameLen
        :pointer,  # File
        :uint,     # LineNo
        :pointer,  # Ty (subroutine type)
        :int,      # IsLocalToUnit
        :int,      # IsDefinition
        :uint,     # ScopeLine
        :uint,     # Flags
        :int       # IsOptimized
      ], :pointer

      # Create subroutine type
      attach_function :LLVMDIBuilderCreateSubroutineType, [
        :pointer,  # Builder
        :pointer,  # File
        :pointer,  # ParameterTypes array
        :uint,     # NumParameterTypes
        :uint      # Flags
      ], :pointer

      # Create basic type
      attach_function :LLVMDIBuilderCreateBasicType, [
        :pointer,  # Builder
        :string,   # Name
        :size_t,   # NameLen
        :uint64,   # SizeInBits
        :uint,     # Encoding
        :uint      # Flags
      ], :pointer

      # Create debug location
      attach_function :LLVMDIBuilderCreateDebugLocation, [
        :pointer,  # Context
        :uint,     # Line
        :uint,     # Column
        :pointer,  # Scope
        :pointer   # InlinedAt
      ], :pointer

      # Create auto variable (local variable)
      attach_function :LLVMDIBuilderCreateAutoVariable, [
        :pointer,  # Builder
        :pointer,  # Scope
        :string,   # Name
        :size_t,   # NameLen
        :pointer,  # File
        :uint,     # LineNo
        :pointer,  # Ty
        :int,      # AlwaysPreserve
        :uint,     # Flags
        :uint      # AlignInBits
      ], :pointer

      # Create parameter variable
      attach_function :LLVMDIBuilderCreateParameterVariable, [
        :pointer,  # Builder
        :pointer,  # Scope
        :string,   # Name
        :size_t,   # NameLen
        :uint,     # ArgNo
        :pointer,  # File
        :uint,     # LineNo
        :pointer,  # Ty
        :int,      # AlwaysPreserve
        :uint      # Flags
      ], :pointer

      # Insert declare record (for alloca) - LLVM 20+
      attach_function :LLVMDIBuilderInsertDeclareRecordAtEnd, [
        :pointer,  # Builder
        :pointer,  # Storage (alloca)
        :pointer,  # VarInfo
        :pointer,  # Expr
        :pointer,  # DebugLoc
        :pointer   # Block (BasicBlock)
      ], :pointer

      # Create expression
      attach_function :LLVMDIBuilderCreateExpression, [
        :pointer,  # Builder
        :pointer,  # Addr array
        :size_t    # Length
      ], :pointer

      # Set subprogram
      attach_function :LLVMSetSubprogram, [:pointer, :pointer], :void

      # Get/Set current debug location
      attach_function :LLVMSetCurrentDebugLocation2, [:pointer, :pointer], :void
      attach_function :LLVMGetCurrentDebugLocation2, [:pointer], :pointer

      # Metadata kind
      attach_function :LLVMGetMDKindIDInContext, [:pointer, :string, :uint], :uint

      # Type array
      attach_function :LLVMDIBuilderGetOrCreateTypeArray, [
        :pointer,  # Builder
        :pointer,  # Data array
        :size_t    # NumElements
      ], :pointer

      # Module flags for DWARF version
      attach_function :LLVMAddModuleFlag, [
        :pointer,  # Module
        :int,      # Behavior (LLVMModuleFlagBehaviorWarning = 1)
        :string,   # Key
        :size_t,   # KeyLen
        :pointer   # Val (Metadata)
      ], :void

      # Convert value to metadata
      attach_function :LLVMValueAsMetadata, [:pointer], :pointer

      # Create constant int
      attach_function :LLVMConstInt, [:pointer, :ulong_long, :int], :pointer

      # Get int types
      attach_function :LLVMInt32TypeInContext, [:pointer], :pointer

      # Get module context
      attach_function :LLVMGetModuleContext, [:pointer], :pointer
    end

    # High-level wrapper for DIBuilder
    class DIBuilder
      attr_reader :builder, :file, :compile_unit

      DWARF_VERSION = 4
      DEBUG_INFO_VERSION = 3  # LLVM debug info version

      def initialize(llvm_module)
        @llvm_module = llvm_module
        @builder = DebugInfoFFI.LLVMCreateDIBuilder(llvm_module.to_ptr)
        @file = nil
        @compile_unit = nil
        @types = {}

        # Set module flags for DWARF
        set_module_debug_flags
      end

      # Set module flags required for DWARF debug info
      def set_module_debug_flags
        mod_ptr = @llvm_module.to_ptr
        ctx = DebugInfoFFI.LLVMGetModuleContext(mod_ptr)
        i32_type = DebugInfoFFI.LLVMInt32TypeInContext(ctx)

        # Add "Dwarf Version" flag
        dwarf_val = DebugInfoFFI.LLVMConstInt(i32_type, DWARF_VERSION, 0)
        dwarf_md = DebugInfoFFI.LLVMValueAsMetadata(dwarf_val)
        key = "Dwarf Version"
        DebugInfoFFI.LLVMAddModuleFlag(mod_ptr, 1, key, key.length, dwarf_md)

        # Add "Debug Info Version" flag
        debug_val = DebugInfoFFI.LLVMConstInt(i32_type, DEBUG_INFO_VERSION, 0)
        debug_md = DebugInfoFFI.LLVMValueAsMetadata(debug_val)
        key2 = "Debug Info Version"
        DebugInfoFFI.LLVMAddModuleFlag(mod_ptr, 1, key2, key2.length, debug_md)
      end

      def create_compile_unit(filename:, directory:, producer: "konpeito")
        @file = DebugInfoFFI.LLVMDIBuilderCreateFile(
          @builder,
          filename, filename.length,
          directory, directory.length
        )

        @compile_unit = DebugInfoFFI.LLVMDIBuilderCreateCompileUnit(
          @builder,
          DebugInfoFFI::DWARF_SOURCE_LANGUAGE_RUBY,
          @file,
          producer, producer.length,
          0,          # isOptimized
          "", 0,      # Flags
          0,          # RuntimeVer
          nil, 0,     # SplitName
          1,          # DWARFEmissionKind::FullDebug
          0,          # DWOId
          0,          # SplitDebugInlining
          0,          # DebugInfoForProfiling
          nil, 0,     # SysRoot
          nil, 0      # SDK
        )
      end

      def create_function(name:, linkage_name: nil, line:, scope: nil)
        linkage_name ||= name
        scope ||= @compile_unit

        # Create subroutine type (void for now)
        type_array_ptr = FFI::MemoryPointer.new(:pointer, 1)
        type_array_ptr.put_pointer(0, nil)  # void return type
        subroutine_type = DebugInfoFFI.LLVMDIBuilderCreateSubroutineType(
          @builder,
          @file,
          type_array_ptr,
          0,
          DebugInfoFFI::DI_FLAG_ZERO
        )

        DebugInfoFFI.LLVMDIBuilderCreateFunction(
          @builder,
          scope,
          name, name.length,
          linkage_name, linkage_name.length,
          @file,
          line,
          subroutine_type,
          1,    # IsLocalToUnit
          1,    # IsDefinition
          line, # ScopeLine
          DebugInfoFFI::DI_FLAG_ZERO,
          0     # IsOptimized
        )
      end

      def create_debug_location(context, line:, column:, scope:)
        DebugInfoFFI.LLVMDIBuilderCreateDebugLocation(
          context,
          line,
          column,
          scope,
          nil  # InlinedAt
        )
      end

      def set_location(builder, location)
        DebugInfoFFI.LLVMSetCurrentDebugLocation2(builder.to_ptr, location)
      end

      def attach_subprogram(function, subprogram)
        DebugInfoFFI.LLVMSetSubprogram(function.to_ptr, subprogram)
      end

      def create_basic_type(name:, size_bits:, encoding:)
        @types[name] ||= DebugInfoFFI.LLVMDIBuilderCreateBasicType(
          @builder,
          name, name.length,
          size_bits,
          encoding,
          DebugInfoFFI::DI_FLAG_ZERO
        )
      end

      def create_empty_expression
        DebugInfoFFI.LLVMDIBuilderCreateExpression(@builder, nil, 0)
      end

      def create_auto_variable(name:, scope:, line:, type:)
        DebugInfoFFI.LLVMDIBuilderCreateAutoVariable(
          @builder,
          scope,
          name, name.length,
          @file,
          line,
          type,
          1,    # AlwaysPreserve
          DebugInfoFFI::DI_FLAG_ZERO,
          0     # AlignInBits
        )
      end

      def insert_declare(storage:, var_info:, location:, block:)
        expr = create_empty_expression
        DebugInfoFFI.LLVMDIBuilderInsertDeclareRecordAtEnd(
          @builder,
          storage.to_ptr,
          var_info,
          expr,
          location,
          block.to_ptr
        )
      end

      def finalize
        DebugInfoFFI.LLVMDIBuilderFinalize(@builder)
      end

      def dispose
        DebugInfoFFI.LLVMDisposeDIBuilder(@builder)
        @builder = nil
      end
    end
  end
end

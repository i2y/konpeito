# frozen_string_literal: true

# CI Diagnostic Script
# Tests each stage of the native compilation pipeline individually,
# reporting PASS/FAIL for each stage to help identify where failures occur.

require "rbconfig"
require "tempfile"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

PASS = "\e[32mPASS\e[0m"
FAIL = "\e[31mFAIL\e[0m"

failures = []

def report(stage, success, detail = nil)
  status = success ? PASS : FAIL
  msg = "  [#{status}] #{stage}"
  msg += " — #{detail}" if detail
  puts msg
  success
end

# --- Environment Info ---
puts "=== Environment ==="
puts "  Ruby:     #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "  DLEXT:    #{RbConfig::CONFIG['DLEXT']}"
puts "  rubyhdrdir: #{RbConfig::CONFIG['rubyhdrdir']}"
puts ""

# --- LLVM Tool Detection ---
puts "=== LLVM Tools ==="
require "konpeito/platform"

%w[llc opt clang].each do |tool|
  path = Konpeito::Platform.find_llvm_tool(tool)
  if path
    version = `#{path} --version 2>&1`.lines.first&.strip rescue "unknown"
    report(tool, true, "#{path} (#{version})")
  else
    failures << "#{tool} not found"
    report(tool, false, "not found")
  end
end
puts ""

# --- CRuby Headers ---
puts "=== CRuby Headers ==="
hdrdir = RbConfig::CONFIG["rubyhdrdir"]
archhdrdir = RbConfig::CONFIG["rubyarchhdrdir"]
ruby_h = File.join(hdrdir, "ruby.h")

report("rubyhdrdir exists", Dir.exist?(hdrdir.to_s), hdrdir)
report("rubyarchhdrdir exists", Dir.exist?(archhdrdir.to_s), archhdrdir)
ok = File.exist?(ruby_h)
failures << "ruby.h not found" unless ok
report("ruby.h exists", ok, ruby_h)
puts ""

# --- Stage 1: LLVM tool smoke test (minimal IR → .o) ---
puts "=== Stage 1: LLVM Tool Smoke Test ==="
dir = Dir.mktmpdir("konpeito_diag_")

begin
  llc = Konpeito::Platform.find_llvm_tool("llc")
  if llc
    minimal_ir = File.join(dir, "smoke.ll")
    smoke_obj = File.join(dir, "smoke.o")
    File.write(minimal_ir, <<~IR)
      define i64 @smoke_add(i64 %a, i64 %b) {
        %r = add i64 %a, %b
        ret i64 %r
      }
    IR
    system("#{llc} -filetype=obj -relocation-model=pic -o #{smoke_obj} #{minimal_ir} 2>&1")
    stage1_ok = File.exist?(smoke_obj) && File.size(smoke_obj) > 0
    failures << "llc smoke test" unless stage1_ok
    report("llc: IR → .o", stage1_ok,
           stage1_ok ? "#{File.size(smoke_obj)} bytes" : "compilation failed")
  else
    failures << "llc not found"
    report("llc: IR → .o", false, "llc not found")
  end

  # --- Stage 2: C compilation with Ruby headers ---
  puts ""
  puts "=== Stage 2: C Compilation with Ruby Headers ==="
  cc = Konpeito::Platform.find_llvm_tool("clang") || "cc"
  init_c = File.join(dir, "test_init.c")
  init_o = File.join(dir, "test_init.o")
  File.write(init_c, <<~C)
    #include <ruby.h>
    void Init_test_diag(void) { }
  C
  cmd = "#{cc} -c -fPIC -I#{hdrdir} -I#{archhdrdir} -o #{init_o} #{init_c} 2>&1"
  cc_output = `#{cmd}`
  stage2_ok = $?.success? && File.exist?(init_o)
  failures << "C compilation with Ruby headers" unless stage2_ok
  report("clang -c (Ruby headers)", stage2_ok,
         stage2_ok ? "#{File.size(init_o)} bytes" : cc_output.strip)

  # --- Stage 3: Full pipeline (Konpeito compile + require + call) ---
  puts ""
  puts "=== Stage 3: Full Konpeito Pipeline ==="
  require "konpeito"

  source_file = File.join(dir, "diag.rb")
  rbs_file = File.join(dir, "diag.rbs")
  shared_ext = RbConfig::CONFIG["DLEXT"]
  output_file = File.join(dir, "diag.#{shared_ext}")

  File.write(source_file, <<~RUBY)
    def diag_add(a, b)
      a + b
    end
  RUBY

  File.write(rbs_file, <<~RBS)
    module TopLevel
      def diag_add: (Integer a, Integer b) -> Integer
    end
  RBS

  begin
    compiler = Konpeito::Compiler.new(source_file: source_file, output_file: output_file, verbose: false)
    compiler.compile
    compile_ok = File.exist?(output_file) && File.size(output_file) > 0
    failures << "Konpeito compile" unless compile_ok
    report("compile (source → .#{shared_ext})", compile_ok,
           compile_ok ? "#{File.size(output_file)} bytes" : "output not generated")

    if compile_ok
      require output_file
      result = diag_add(3, 4)
      call_ok = result == 7
      failures << "require + call" unless call_ok
      report("require + call verification", call_ok,
             call_ok ? "diag_add(3, 4) = #{result}" : "expected 7, got #{result}")
    else
      failures << "require + call"
      report("require + call verification", false, "skipped (compile failed)")
    end
  rescue => e
    failures << "Konpeito pipeline: #{e.class}: #{e.message}"
    report("Konpeito pipeline", false, "#{e.class}: #{e.message}")
  end
ensure
  FileUtils.rm_rf(dir)
end

puts ""
if failures.empty?
  puts "=== All stages PASSED ==="
  exit 0
else
  puts "=== #{failures.size} failure(s) ==="
  failures.each { |f| puts "  - #{f}" }
  exit 1
end

# frozen_string_literal: true

module Conformance
  class Comparator
    ParsedResult = Struct.new(:pass_count, :fail_count, :total, :lines, keyword_init: true)

    def parse_output(stdout)
      lines = stdout.lines.map(&:chomp).select { |l| l.start_with?("PASS:", "FAIL:", "SUMMARY:") }
      pass_count = 0
      fail_count = 0

      lines.each do |line|
        case line
        when /\ASUMMARY: (\d+) passed, (\d+) failed/
          pass_count = $1.to_i
          fail_count = $2.to_i
        end
      end

      ParsedResult.new(
        pass_count: pass_count,
        fail_count: fail_count,
        total: pass_count + fail_count,
        lines: lines
      )
    end

    def compare(reference, target)
      ref_lines = reference.lines.select { |l| l.start_with?("PASS:", "FAIL:") }
      tgt_lines = target.lines.select { |l| l.start_with?("PASS:", "FAIL:") }

      diffs = []
      max_len = [ref_lines.length, tgt_lines.length].max

      max_len.times do |i|
        ref_line = ref_lines[i]&.chomp
        tgt_line = tgt_lines[i]&.chomp

        if ref_line != tgt_line
          diffs << { index: i, expected: ref_line, actual: tgt_line }
        end
      end

      diffs
    end
  end
end

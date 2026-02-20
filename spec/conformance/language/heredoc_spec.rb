require_relative "../lib/konpeito_spec"

# Based on ruby/spec language/heredoc_spec.rb

# Heredoc with <<identifier, interpolated
def test_heredoc_with_identifier_interpolated
  ip = "xxx"
  s = <<HERE
foo bar#{ip}
HERE
  assert_equal("foo barxxx\n", s, "allows HEREDOC with <<identifier, interpolated")
end

# Heredoc with <<"identifier", interpolated
def test_heredoc_with_double_quoted_identifier
  ip = "xxx"
  s = <<"HERE"
foo bar#{ip}
HERE
  assert_equal("foo barxxx\n", s, 'allows HEREDOC with <<"identifier", interpolated')
end

# Heredoc with <<'identifier', no interpolation
def test_heredoc_with_single_quoted_identifier
  s = <<'HERE'
foo bar#{@ip}
HERE
  assert_equal('foo bar#{@ip}' + "\n", s, "allows HEREDOC with <<'identifier', no interpolation")
end

# Heredoc with <<-identifier, allowing indented closing identifier
def test_heredoc_with_dash_identifier_interpolated
  ip = "xxx"
  s = <<-HERE
    foo bar#{ip}
    HERE
  assert_equal("    foo barxxx\n", s, "allows HEREDOC with <<-identifier, indented closing identifier, interpolated")
end

# Heredoc with <<-'identifier', indented closing, no interpolation
def test_heredoc_with_dash_single_quoted_no_interpolation
  s = <<-'HERE'
    foo bar#{@ip}
    HERE
  assert_equal('    foo bar#{@ip}' + "\n", s, "allows HEREDOC with <<-'identifier', indented closing, no interpolation")
end

# Squiggly heredoc <<~identifier strips common leading whitespace, interpolated
def test_squiggly_heredoc_strips_indentation
  s = <<~HERE
    a
      b
        c
  HERE
  assert_equal("a\n  b\n    c\n", s, "squiggly heredoc selects least-indented line and removes its indentation")
end

# Squiggly heredoc <<~'identifier', no interpolation
def test_squiggly_heredoc_single_quoted_no_interpolation
  s = <<~'HERE'
    singlequoted #{"interpolated"}
  HERE
  assert_equal("singlequoted \#{\"interpolated\"}\n", s, "allows squiggly HEREDOC with <<~'identifier', no interpolation")
end

# Squiggly heredoc with interpolation
def test_squiggly_heredoc_with_interpolation
  value = "interpolated"
  s = <<~HERE
    unquoted #{value}
  HERE
  assert_equal("unquoted interpolated\n", s, "allows squiggly HEREDOC with <<~identifier, interpolated")
end

# Heredoc preserves newlines in multiline content
def test_heredoc_preserves_newlines
  s = <<HERE
line one
line two
line three
HERE
  assert_equal("line one\nline two\nline three\n", s, "heredoc preserves newlines in multiline content")
end

# Squiggly heredoc least-indented on last line
def test_squiggly_heredoc_least_indented_last_line
  s = <<~HERE
        a
      b
    c
  HERE
  assert_equal("    a\n  b\nc\n", s, "squiggly heredoc removes least indentation when last line is least indented")
end

def run_tests
  spec_reset
  test_heredoc_with_identifier_interpolated
  test_heredoc_with_double_quoted_identifier
  test_heredoc_with_single_quoted_identifier
  test_heredoc_with_dash_identifier_interpolated
  test_heredoc_with_dash_single_quoted_no_interpolation
  test_squiggly_heredoc_strips_indentation
  test_squiggly_heredoc_single_quoted_no_interpolation
  test_squiggly_heredoc_with_interpolation
  test_heredoc_preserves_newlines
  test_squiggly_heredoc_least_indented_last_line
  spec_summary
end

run_tests

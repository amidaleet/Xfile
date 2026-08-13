require_relative '../sd_specs'

# Search for lines:
# Tests Failed: 3 failed, 0 skipped, 3246 total (10.471 seconds)
# Tests Passed: 0 failed, 0 skipped, 632 total (5.941 seconds)
#
# Writes lines to output, sample:
# "unit": { "passed": false, "failed": 3, "skipped": 0, "total": 3246 },
def add_test_result_from_log_with_summary(output, path, name)
  logged_result = `grep -Eo 'Tests (Passed|Failed): [0-9]+ failed, [0-9]+ skipped, [0-9]+ total' '#{path}'`
  report_line = logged_result.split("\n").first
  return unless report_line && !report_line.empty?

  json = String.new
  int_value = lambda do |key|
    ", \"#{key}\": " + report_line.match(/[0-9]+ #{key}/).to_s.delete_suffix(" #{key}")
  end
  json << "\"passed\": #{report_line.match?('Tests Passed:')}"
  json << int_value.call('failed')
  json << int_value.call('skipped')
  json << int_value.call('total')

  output << ",\n" unless output.empty?
  output << "  \"#{name}\": { #{json} }"
end

# Search for lines:
# ▸ Test Suite 'All tests' passed at 2024-09-09 12:01:02.764.
# ▸ Executed 7 tests, with 0 failures (0 unexpected) in 0.033 (0.041) seconds
#
# Writes lines to output, sample:
# "unit": { "passed": false, "failed": 3, "skipped": 0, "total": 3246 },
def add_test_result_from_log_without_summary(output, path, name, is_doubled_output_on_failure)
  logged_result = `grep -A 1 -Eo "Test Suite 'All tests' (passed|failed)" '#{path}'`

  matches_arr = logged_result.gsub(/\e\[(\d+)m/, '').split("--")
  return unless matches_arr && !matches_arr.empty?

  scheme_total = 0
  scheme_failed = 0
  scheme_skipped = 0
  is_passed = true

  for match in matches_arr
    total = match.match(/[0-9]+ tests/).to_s.delete_suffix(' tests').to_i
    failed = match.match(/[0-9]+ failures/).to_s.delete_suffix(' failures').to_i
    skipped = match.match(/[0-9]+ test[s]? skipped/).to_s.delete_suffix(' tests skipped').delete_suffix(' test skipped').to_i

    is_passed = false if match.match?("'All tests' failed")

    scheme_total += total
    scheme_failed += failed
    scheme_skipped += skipped
  end

  # fastlane prints all output on failure, which doubles xcbeautify output
  # Long known and unfixed issue: https://github.com/fastlane/fastlane/issues/9820
  if is_doubled_output_on_failure && !is_passed
    scheme_total /= 2
    scheme_failed /= 2
    scheme_skipped /= 2
  end

  output << ",\n" unless output.empty?
  output << "  \"#{name}\": { \"passed\": #{is_passed}, \"failed\": #{scheme_failed}, \"skipped\": #{scheme_skipped}, \"total\": #{scheme_total} }"
end

# Searching for table:
# +--------------------------------+
# |          Test Results          |
# +-------------------------+------+
# | Number of tests         | 2592 |
# | Number of tests skipped | 15   |
# | Number of failures      | 1    |
# +-------------------------+------+
#
# Writes lines to output, sample:
# "unit": { "passed": false, "failed": 3, "skipped": 0, "total": 3246 },
def add_test_result_from_fastlane_log(output, path, name)
  fastlane_table = `grep -A 4 -Eo '\\| +Test Results +\\|' '#{path}'`

  if fastlane_table.empty?
    # Fallback if no failure table present
    add_test_result_from_log_without_summary(output, path, name, true)
    return
  end
  fastlane_table = fastlane_table.gsub(/\e\[(\d+)m/, '')

  total = fastlane_table.match(/Number of tests.*/).to_s.match(/[0-9]+/).to_s
  skipped = fastlane_table.match(/Number of tests skipped.*/).to_s.match(/[0-9]+/).to_s
  failed = fastlane_table.match(/Number of failures.*/).to_s.match(/[0-9]+/).to_s

  total = 0 if total.empty?
  skipped = 0 if skipped.empty?
  failed = 0 if failed.empty?

  is_passed = failed.to_i == 0 && total.to_i > 0

  output << ",\n" unless output.empty?
  output << "  \"#{name}\": { \"passed\": #{is_passed}, \"failed\": #{failed}, \"skipped\": #{skipped}, \"total\": #{total} }"
end

# TestSummary were removed since 2.6.0
# Will peak most suitable algorithm
#
# Searching for SemVer lines sample:
# ▸ ----- xcbeautify -----
# ▸ Version: 2.11.0
# ▸ ----------------------
def add_test_result(output, path, name, is_fastlane)
  xcbeautify_version_match = `grep -A 1 -Eo "\\- xcbeautify \\-" '#{path}'`.gsub(/\e\[(\d+)m/, '')

  v_parts = xcbeautify_version_match.match(/[0-9]+\.[0-9]+\.[0-9]+/).to_s.split('.')
  major = v_parts[0].to_i
  minor = v_parts[1].to_i

  if major < 2 || (major == 2 && minor < 6)
    add_test_result_from_log_with_summary(output, path, name)
  elsif is_fastlane
    add_test_result_from_fastlane_log(output, path, name)
  else
    add_test_result_from_log_without_summary(output, path, name, false)
  end
end

log_files = []

ARGV.each do |arg|
  if arg.start_with?('p_', 'f_')
    log_files << arg
  end
end

output = String.new

for path in log_files do
  is_fastlane = false

  if path.start_with?('p_')
    path = path.delete_prefix('p_')
  elsif path.start_with?('f_')
    path = path.delete_prefix('f_')
    is_fastlane = true
  end

  next unless File.exist?(path)

  name = path.match(/[a-z_]+_tests/).to_s.delete_suffix('_tests')
  add_test_result(output, path, name, is_fastlane)
end

# Output sample:
# {
#   "swift_tools": { "passed": true, "failed": 0, "skipped": 0, "total": 632 },
#   "unit": { "passed": false, "failed": 3, "skipped": 0, "total": 3246 },
#   "snapshot": { "passed": true, "failed": 0, "skipped": 2, "total": 587 }
# }
if output.empty?
  # safe json to parse
  puts "{}"
else
  puts "{\n#{output}\n}"
end

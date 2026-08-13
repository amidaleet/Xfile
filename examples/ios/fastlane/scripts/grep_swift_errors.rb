require_relative '../sd_specs'

def add_compilation_errors(message, path, length_limit, name, picked_lines)
  errors = `grep -E '^❌' '#{path}' | grep -Eo '[a-zA-Z0-9+_]+\.swift:[0-9]+:[0-9]+: .*$'`
  new_part = String.new
  tail = "```"

  for line in errors.split("\n")
    next if line == '--'

    new_line = line.match?(/^[\t ].+/) ? "#{line.strip!}\n" : "#{line}\n"
    new_line.gsub!(/\x1b\[[0-9;]*m/, '')
    next if picked_lines.include?(new_line)

    # 'raw' line for de-duplication
    picked_lines << new_line

    if new_part.empty?
      new_line = "\n#{name} compile\n```swift\n#{new_line}"
    end

    break if message.length + new_part.length + new_line.length + tail.length >= length_limit

    new_part << new_line
  end
  unless new_part.empty?
    message << new_part
    message << tail
  end
end

def add_failed_tests(message, path, length_limit, name, picked_lines)
  errors = `grep -A 15 -Eo '^Failing tests:$' '#{path}'`
  new_part = String.new
  tail = "```"

  for line in errors.split("\n").drop(1)
    if line.match?(/^[\t ].+/)
      new_line = "#{line.strip!}\n"
      new_line.gsub!(/\x1b\[[0-9;]*m/, '')
      next if picked_lines.include?(new_line)

      # 'raw' line for de-duplication
      picked_lines << new_line

      if new_part.empty?
        new_line = "\n#{name}\n```swift\n#{new_line}"
      end

      break if message.length + new_part.length + new_line.length + tail.length >= length_limit

      new_part << new_line
    else
      break
    end
  end
  unless new_part.empty?
    message << new_part
    message << tail
  end
end

reserved_length = 0
log_files = []

ARGV.each do |arg|
  if arg.start_with?('p_')
    log_files << arg.delete_prefix('p_')
  else
    reserved_length = arg.to_i
  end
end

length_limit = SD_SPEC::MM_MESSAGE_MAX_LENGTH - reserved_length
message = String.new
picked_lines = Set.new

for path in log_files do
  next unless File.exist?(path)
  break if message.length >= length_limit

  name = path.match(/[a-z_]+_tests/)
  add_compilation_errors(message, path, length_limit, name, picked_lines)

  break if message.length >= length_limit

  add_failed_tests(message, path, length_limit, name, picked_lines)
end

unless message.empty?
  puts message
end

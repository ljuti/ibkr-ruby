# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

task default: %i[spec standard]

desc "Run tests with code coverage"
task :coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task["spec"].invoke

  if File.exist?("coverage/.last_run.json")
    require "json"
    data = JSON.parse(File.read("coverage/.last_run.json"))
    coverage = data["result"]["line"]

    puts "\n" + "=" * 60
    puts " Code Coverage: #{coverage}%"
    puts "=" * 60
    puts " HTML report: coverage/index.html"
    puts " Run 'open coverage/index.html' to view detailed report"
    puts "=" * 60
  end
end

desc "Run tests with coverage and open HTML report"
task coverage_open: :coverage do
  system("open coverage/index.html") if RUBY_PLATFORM.match?(/darwin/)
end

desc "Display code statistics"
task :stats do
  require "date"

  puts "\n" + "=" * 60
  puts " IBKR Ruby Gem - Code Statistics"
  puts " Generated: #{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}"
  puts "=" * 60

  # Count lines in production code
  lib_files = Dir["lib/**/*.rb"]
  lib_lines = lib_files.sum { |f| File.readlines(f).size }

  # Count lines in test code
  spec_files = Dir["spec/**/*.rb"]
  spec_lines = spec_files.sum { |f| File.readlines(f).size }

  # Count lines by component
  components = {}
  lib_files.each do |file|
    component = file.split("/")[1..2].join("/").sub(".rb", "")
    lines = File.readlines(file).size
    components[component] = (components[component] || 0) + lines
  end

  puts "\n## Production Code (lib/)"
  puts "-" * 40
  printf "%-30s %10s\n", "Component", "Lines"
  puts "-" * 40

  components.sort_by { |_, v| -v }.first(10).each do |component, lines|
    printf "%-30s %10d\n", component, lines
  end

  puts "-" * 40
  printf "%-30s %10d\n", "Total lib/", lib_lines

  puts "\n## Test Code (spec/)"
  puts "-" * 40
  printf "%-30s %10d\n", "Total spec/", spec_lines

  # Calculate ratio
  ratio = (spec_lines.to_f / lib_lines).round(2)

  puts "\n## Summary"
  puts "-" * 40
  printf "%-30s %10d\n", "Production code (lib/)", lib_lines
  printf "%-30s %10d\n", "Test code (spec/)", spec_lines
  printf "%-30s %10d\n", "Total Ruby code", lib_lines + spec_lines
  printf "%-30s %10.2f:1\n", "Test-to-code ratio", ratio

  puts "\n## File Counts"
  puts "-" * 40
  printf "%-30s %10d\n", "Production files", lib_files.size
  printf "%-30s %10d\n", "Test files", spec_files.size
  printf "%-30s %10d\n", "Total Ruby files", lib_files.size + spec_files.size

  puts "=" * 60
  puts
end

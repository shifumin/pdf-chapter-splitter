# frozen_string_literal: true

require "bundler/setup"
require_relative "../pdf_chapter_splitter"
require "fileutils"
require "tmpdir"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Helper method to create a temporary directory for tests
  def temp_dir
    @temp_dir ||= Dir.mktmpdir
  end

  # Clean up temp directory after each test
  config.after do
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    @temp_dir = nil
  end

  # Helper to capture stdout and stderr
  def capture_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  # Helper to run the script with arguments
  def run_script(*args)
    # Save original ARGV
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(args)

    # Capture output and run
    stdout, stderr = capture_output do
      PDFChapterSplitter.new.run
    rescue SystemExit => e
      # Capture exit status
      @exit_status = e.status
    end

    [stdout, stderr, @exit_status]
  ensure
    # Restore original ARGV
    ARGV.clear
    ARGV.concat(original_argv)
    @exit_status = nil
  end
end

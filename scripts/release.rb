#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require "optparse"
require "fileutils"

# Release automation script for gran and giblish gems
class ReleaseManager
  REPO_ROOT = Pathname.new(__dir__).parent
  GRAN_DIR = REPO_ROOT / "gran"
  GIBLISH_DIR = REPO_ROOT / "giblish"

  VALID_PROJECTS = %w[gran giblish both].freeze
  VALID_COMMANDS = %w[prepare publish all].freeze
  VALID_VERSION_TYPES = %w[major minor patch].freeze

  attr_reader :project, :command, :version_type, :dry_run, :yes, :specific_version

  def initialize(args)
    @dry_run = false
    @yes = false
    @specific_version = nil
    parse_options(args)
    validate_args
  end

  def run
    puts "\n=== Release Manager ==="
    puts "Project: #{project}"
    puts "Command: #{command}"
    puts "Version: #{version_type || specific_version}"
    puts "Dry-run: #{dry_run}"
    puts "========================\n\n"

    case command
    when "prepare"
      prepare_release
    when "publish"
      publish_release
    when "all"
      prepare_release
      publish_release
    end
  end

  private

  def parse_options(args)
    OptionParser.new do |opts|
      opts.banner = "Usage: release.rb [options] PROJECT COMMAND [VERSION]"
      opts.separator ""
      opts.separator "PROJECT: #{VALID_PROJECTS.join(", ")}"
      opts.separator "COMMAND: #{VALID_COMMANDS.join(", ")}"
      opts.separator "VERSION: #{VALID_VERSION_TYPES.join(", ")} or specific version (e.g., 0.2.0)"
      opts.separator ""
      opts.separator "Options:"

      opts.on("-n", "--dry-run", "Show what would happen without doing it") do
        @dry_run = true
      end

      opts.on("-y", "--yes", "Skip confirmation prompts") do
        @yes = true
      end

      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit 0
      end
    end.parse!(args)

    @project = args[0]
    @command = args[1]

    # Parse version argument
    if args[2]
      if VALID_VERSION_TYPES.include?(args[2])
        @version_type = args[2]
      elsif args[2] =~ /^\d+\.\d+\.\d+$/
        @specific_version = args[2]
      else
        puts "ERROR: Invalid version '#{args[2]}'. Must be #{VALID_VERSION_TYPES.join(", ")} or a version number (e.g., 0.2.0)"
        exit 1
      end
    end
  end

  def validate_args
    unless VALID_PROJECTS.include?(project)
      puts "ERROR: Invalid project '#{project}'. Must be one of: #{VALID_PROJECTS.join(", ")}"
      exit 1
    end

    unless VALID_COMMANDS.include?(command)
      puts "ERROR: Invalid command '#{command}'. Must be one of: #{VALID_COMMANDS.join(", ")}"
      exit 1
    end

    if command != "publish" && version_type.nil? && specific_version.nil?
      puts "ERROR: VERSION argument required for '#{command}' command"
      exit 1
    end
  end

  def prepare_release
    if project == "both"
      prepare_gran
      prepare_giblish
    elsif project == "gran"
      prepare_gran
    else
      prepare_giblish
    end
  end

  def publish_release
    if project == "both"
      publish_gran
      wait_for_rubygems("gran")
      publish_giblish
    elsif project == "gran"
      publish_gran
    else
      publish_giblish
    end
  end

  def prepare_gran
    puts "\n📦 Preparing gran for release...\n"
    with_dir(GRAN_DIR) do
      run_safety_checks("gran")
      new_version = bump_version(GRAN_DIR / "lib/gran/version.rb")
      update_changelog("gran", new_version)
      build_gem("gran")
      create_git_commit_and_tag("gran", new_version)
      success("Gran prepared for release: v#{new_version}")
    end
  end

  def prepare_giblish
    puts "\n📦 Preparing giblish for release...\n"
    with_dir(GIBLISH_DIR) do
      run_safety_checks("giblish")
      check_gran_dependency
      new_version = bump_version(GIBLISH_DIR / "lib/giblish/version.rb")
      update_changelog("giblish", new_version)
      build_gem("giblish")
      create_git_commit_and_tag("giblish", new_version)
      success("Giblish prepared for release: v#{new_version}")
    end
  end

  def publish_gran
    puts "\n🚀 Publishing gran to RubyGems...\n"
    with_dir(GRAN_DIR) do
      push_to_github("gran")
      publish_gem("gran")
      success("Gran published!")
    end
  end

  def publish_giblish
    puts "\n🚀 Publishing giblish to RubyGems...\n"
    with_dir(GIBLISH_DIR) do
      push_to_github("giblish")
      publish_gem("giblish")
      success("Giblish published!")
    end
  end

  # Safety Checks
  def run_safety_checks(project_name)
    step("Running safety checks for #{project_name}")
    check_git_status
    check_on_main_branch
    run_tests
    run_linter
  end

  def check_git_status
    output = `git status --porcelain`.strip
    unless output.empty?
      error("Working directory is not clean. Commit or stash changes first.")
    end
  end

  def check_on_main_branch
    branch = `git rev-parse --abbrev-ref HEAD`.strip
    unless branch == "main"
      unless confirm("You are on branch '#{branch}', not 'main'. Continue anyway?")
        error("Aborted. Switch to main branch or use --yes to override.")
      end
    end
  end

  def run_tests
    step("Running tests")
    unless system("bundle exec rake test > /dev/null 2>&1")
      error("Tests failed! Fix tests before releasing.")
    end
  end

  def run_linter
    step("Running linter")
    unless system("bundle exec rake standard > /dev/null 2>&1")
      error("Linter failed! Fix linting issues before releasing.")
    end
  end

  def check_gran_dependency
    gemspec_path = GIBLISH_DIR / "giblish.gemspec"
    content = File.read(gemspec_path)

    if content =~ /add_runtime_dependency\s+"gran",\s+"~>\s*([\d.]+)"/
      current_dep = $1
      latest_gran = get_latest_rubygems_version("gran")

      if latest_gran && Gem::Version.new(latest_gran) > Gem::Version.new(current_dep)
        puts "⚠️  Gran dependency in giblish.gemspec is #{current_dep}, but #{latest_gran} is available on RubyGems"
        if confirm("Update gran dependency to ~> #{latest_gran}?")
          update_gran_dependency(latest_gran)
        end
      end
    end
  end

  def update_gran_dependency(version)
    gemspec_path = GIBLISH_DIR / "giblish.gemspec"
    content = File.read(gemspec_path)
    content.gsub!(/(add_runtime_dependency\s+"gran",\s+)"~>\s*[\d.]+"/,
                  "\\1\"~> #{version}\"")

    if dry_run
      puts "[DRY-RUN] Would update gran dependency to ~> #{version}"
    else
      File.write(gemspec_path, content)
      puts "✓ Updated gran dependency to ~> #{version}"
    end
  end

  # Version Management
  def bump_version(version_file)
    current_version = extract_version(version_file)
    new_version = calculate_new_version(current_version)

    puts "Current version: #{current_version}"
    puts "New version: #{new_version}"

    unless confirm("Bump version to #{new_version}?")
      error("Aborted by user")
    end

    update_version_file(version_file, current_version, new_version)
    new_version
  end

  def extract_version(version_file)
    content = File.read(version_file)
    if content =~ /VERSION\s*=\s*"([\d.]+)"/
      $1
    else
      error("Could not find VERSION in #{version_file}")
    end
  end

  def calculate_new_version(current)
    return specific_version if specific_version

    parts = current.split(".").map(&:to_i)
    case version_type
    when "major"
      "#{parts[0] + 1}.0.0"
    when "minor"
      "#{parts[0]}.#{parts[1] + 1}.0"
    when "patch"
      "#{parts[0]}.#{parts[1]}.#{parts[2] + 1}"
    end
  end

  def update_version_file(version_file, old_version, new_version)
    content = File.read(version_file)
    content.gsub!(/VERSION\s*=\s*"#{Regexp.escape(old_version)}"/,
                  "VERSION = \"#{new_version}\"")

    if dry_run
      puts "[DRY-RUN] Would update #{version_file.basename} to #{new_version}"
    else
      File.write(version_file, content)
      puts "✓ Updated #{version_file.basename}"
    end
  end

  # Changelog
  def update_changelog(project, version)
    step("Updating CHANGELOG")
    puts "⚠️  Please update the CHANGELOG manually with changes for v#{version}"
    puts "Press Enter when done..."
    gets unless yes
  end

  # Gem Operations
  def build_gem(project)
    step("Building #{project} gem")

    if dry_run
      puts "[DRY-RUN] Would run: gem build #{project}.gemspec"
    else
      unless system("gem build #{project}.gemspec")
        error("Failed to build gem")
      end
      puts "✓ Gem built successfully"
    end
  end

  def publish_gem(project)
    gem_file = Dir.glob("#{project}-*.gem").max_by { |f| File.mtime(f) }

    unless gem_file
      error("No gem file found to publish")
    end

    step("Publishing #{gem_file}")

    unless confirm("Push #{gem_file} to RubyGems.org?")
      error("Aborted by user")
    end

    if dry_run
      puts "[DRY-RUN] Would run: gem push #{gem_file}"
    else
      unless system("gem push #{gem_file}")
        error("Failed to publish gem")
      end
      puts "✓ Gem published successfully"
    end
  end

  # Git Operations
  def create_git_commit_and_tag(project, version)
    tag_name = "#{project}-v#{version}"
    commit_message = "Release #{project} v#{version}"

    step("Creating git commit and tag")

    if dry_run
      puts "[DRY-RUN] Would run:"
      puts "  git add ."
      puts "  git commit -m '#{commit_message}'"
      puts "  git tag -a #{tag_name} -m '#{commit_message}'"
    else
      system("git add .")
      unless system("git commit -m '#{commit_message}'")
        error("Failed to create commit")
      end
      unless system("git tag -a #{tag_name} -m '#{commit_message}'")
        error("Failed to create tag")
      end
      puts "✓ Created commit and tag: #{tag_name}"
    end
  end

  def push_to_github(project)
    step("Pushing to GitHub")

    unless confirm("Push commits and tags to GitHub?")
      error("Aborted by user")
    end

    if dry_run
      puts "[DRY-RUN] Would run:"
      puts "  git push origin main"
      puts "  git push origin --tags"
    else
      unless system("git push origin main")
        error("Failed to push commits")
      end
      unless system("git push origin --tags")
        error("Failed to push tags")
      end
      puts "✓ Pushed to GitHub"
    end
  end

  # Helpers
  def wait_for_rubygems(gem_name)
    return if dry_run

    puts "\n⏳ Waiting for #{gem_name} to appear on RubyGems.org..."
    puts "Press Enter when #{gem_name} is available on RubyGems.org..."
    gets unless yes
  end

  def get_latest_rubygems_version(gem_name)
    output = `gem search ^#{gem_name}$ --remote 2>/dev/null`
    if output =~ /#{gem_name}\s+\(([\d.]+)\)/
      $1
    end
  end

  def with_dir(dir)
    original_dir = Dir.pwd
    Dir.chdir(dir)
    yield
  ensure
    Dir.chdir(original_dir)
  end

  def confirm(message)
    return true if yes
    print "#{message} (y/N): "
    response = gets.strip.downcase
    response == "y" || response == "yes"
  end

  def step(message)
    puts "\n→ #{message}..."
  end

  def success(message)
    puts "\n✓ #{message}\n"
  end

  def error(message)
    puts "\n✗ ERROR: #{message}\n"
    exit 1
  end
end

# Run the script
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: release.rb [options] PROJECT COMMAND [VERSION]"
    puts "Run with --help for more information"
    exit 1
  end

  manager = ReleaseManager.new(ARGV)
  manager.run
end

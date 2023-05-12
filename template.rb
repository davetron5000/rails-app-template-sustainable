require "bundler"
require "shellwords"
require "fileutils"
require "tmpdir"

RAILS_REQUIREMENT = "~> 7.0.4.3".freeze

def apply_template!

  add_template_repository_to_source_path

  assert_minimum_rails_version
  assert_valid_options
  assert_postgres

  gem "brakeman"
  gem "bundler-audit"
  gem "lograge"
  gem "sidekiq"
  gem_group :development, :test do
    gem "dotenv-rails"
    gem "factory_bot_rails"
    gem "foreman"
    gem "faker"
  end

  template "README.md.tt", force: true
  remove_file "README.rdoc"

  template ".env.development.tt"
  template ".env.test.tt"
  template ".gitignore.tt", force: true

  template "bin/setup.tt", force: true
  template "bin/ci.tt"
  template "bin/run.tt"
  template "bin/sql.tt"
  template "bin/db-migrate.tt"
  template "bin/db-rollback.tt"
  template "bin/release.tt"
  template "Procfile.tt"

  remove_file "config/database.yml"
  remove_file "config/secrets.yml"

  template "lib/tasks/redis.rake.tt"

  insert_into_file "config/application.rb",
    before: /^  end\s*$/ do
      [
        "    # We will use the fully-armed and operational power of Postgres",
        "    # and that means using SQL-based structure.",
        "    config.active_record.schema_format = :sql",
        "",
        "    config.generators do |g|",
        "      # We don't want per-resource stylesheets since",
        "      # that is not how stylesheets work.",
        "      g.stylesheets false",
        "",
        "      # We don't want per-resource helpers because",
        "      # helpers are global anyway and we don't want",
        "      # a ton of them.",
        "      g.helper false",
        "    end",
      ].join("\n") + "\n"
    end

  remove_file "db/schema.rb" if File.exist?("db/schema.rb")

  copy_file "lib/generators/service/USAGE"
  copy_file "lib/generators/service/service_generator.rb"
  copy_file "lib/generators/service/templates/service.erb"
  copy_file "lib/generators/service/templates/service_test.erb"
  copy_file "lib/logging/logs.rb"
  copy_file "lib/rails_ext/active_record_timestamps_uses_timestamp_with_time_zone.rb"
  copy_file "lib/templates/rails/job/job.rb.tt"
  copy_file "config/initializers/postgres.rb"
  copy_file "config/initializers/sidekiq.rb"

  insert_into_file "config/routes.rb",
    "require \"sidekiq/web\"\n\n",
    before: "Rails.application.routes.draw do"

  insert_into_file "config/routes.rb", before: /^end\s*$/ do
    [
      "",
      "  if !Rails.env.development?",
      "    Sidekiq::Web.use Rack::Auth::Basic do |username, password|",
      "      username == ENV.fetch(\"SIDEKIQ_WEB_USER\") &&",
      "        password == ENV.fetch(\"SIDEKIQ_WEB_PASSWORD\")",
      "    end",
      "  end",
      "  mount Sidekiq::Web => \"/sidekiq\"",
    ].join("\n")
  end

  copy_file "app/jobs/application_job.rb", force: true
  copy_file "app/services/application_service.rb", force: true

  insert_into_file "test/test_helper.rb", after: "require \"rails/test_help\"" do
    [
      "",
      "require \"minitest/autorun\"",
      "require \"minitest/reporters\"",
      "",
      "Minitest::Reporters.use!",
      "unless ENV[\"MINITEST_REPORTER\"]",
      "  Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new",
      "end",
    ].join("\n")
  end
  gsub_file "test/test_helper.rb",
    "# Add more helper methods to be used by all tests here..." do
      [
        "include FactoryBot::Syntax::Methods",
        "",
        "  # Used to indicate assertions that confidence check test",
        "  # set up conditions",
        "  def confidence_check(context=nil, &block)",
        "    block.()",
        "  rescue Exception",
        "    puts context.inspect",
        "    raise",
        "  end",
        "",
        "  # Used inside a test to indicate we haven't implemented it yet",
        "  def not_implemented!",
        "    skip(\"not implemented yet\")",
        "  end",
      ].join("\n")
    end

  copy_file "test/lint_factories_test.rb"
  clean_up_gemfile
end

def run_with_clean_bundler_env(cmd)
  success = if defined?(Bundler)
              Bundler.with_clean_env { run(cmd) }
            else
              run(cmd)
            end
  unless success
    puts "Command failed, exiting: #{cmd}"
    exit(1)
  end
end

def assert_minimum_rails_version
  requirement = Gem::Requirement.new(RAILS_REQUIREMENT)
  rails_version = Gem::Version.new(Rails::VERSION::STRING)
  return if requirement.satisfied_by?(rails_version)

  fail "This template reqires Rails #{RAILS_REQUIREMENT}, but you are using #{rails_version}"
end

def assert_postgres
  return if IO.read("Gemfile") =~ /^\s*gem ['"]pg['"]/
  fail Rails::Generators::Error,
       "This template requires PostgreSQL, "\
       "but the pg gem isn’t present in your Gemfile. Use -d postgresql to rails new"
end

def assert_valid_options
  valid_options = {
    skip_gemfile: false,
    skip_git: false,
    skip_system_test: false,
    skip_test: false,
    skip_test_unit: false,
    edge: false,
  }
  valid_options.each do |key, expected|
    if expected == false
      next unless options.key?(key)
    end
    actual = options[key]
    unless actual == expected
      fail Rails::Generators::Error, "Unsupported option: #{key}=#{actual}"
    end
  end
end

# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    source_paths.unshift(tempdir = Dir.mktmpdir("rails-app-template-sustainable-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/davetron5000/rails-app-template-sustainable.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{rails-app-template-sustainable/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

require "thor"
class Thor::Actions::InjectIntoFile

protected

  # Copied from lib/thor/actions/inject_into_file.rb so I can 
  # raise if the regexp fails
  def replace!(regexp, string, force)
    return if pretend?
    content = File.read(destination)
    if force || !content.include?(replacement)
      # BEGIN CHANGE
      result = content.gsub!(regexp, string)
      if result.nil?
        raise "Regexp didn't match: #{regexp}:\n#{string}"
      end
      # END CHANGE
      # ORIGINAL CODE
      # content.gsub!(regexp, string)
      # END ORIGINAL CODE
      File.open(destination, "wb") { |file| file.write(content) }
    end
  end
end

module Thor::Actions
  # Copied from lib/thor/actions/file_manipulation.rb
  def gsub_file(path, flag, *args, &block)
    return unless behavior == :invoke
    config = args.last.is_a?(Hash) ? args.pop : {}

    path = File.expand_path(path, destination_root)
    say_status :gsub, relative_to_original_destination_root(path), config.fetch(:verbose, true)

    unless options[:pretend]
      content = File.binread(path)
      # BEGIN CHANGE
      result = content.gsub!(flag, *args, &block)
      if result.nil?
        raise "Regexp didn't match #{flag}:\n#{content}"
      end
      # END CHANGE
      # ORIGINAL CODE
      # content.gsub!(flag, *args, &block)
      # END ORIGINAL CODE
      File.open(path, "wb") { |file| file.write(content) }
    end
  end
end

apply_template!

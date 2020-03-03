require "bundler"
require "shellwords"
require "fileutils"
require "tmpdir"

RAILS_REQUIREMENT = "~> 6.0.0".freeze

def apply_template!

  add_template_repository_to_source_path

  assert_minimum_rails_version
  assert_valid_options
  assert_postgres

  template "Gemfile.tt", force: true

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

  template "lib/tasks/sidekiq.rake.tt"

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

  gsub_file "config/environments/production.rb",
    "config.log_level = :debug",
    "config.log_level = :info"

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

  insert_into_file "test/test_helper.rb", after: "require 'rails/test_help'" do
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
        "  # Used to indicate assertions that sanity check test",
        "  # set up conditions",
        "  def sanity_check(context=nil, &block)",
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
    skip_listen: true,
    skip_spring: true,
    skip_turbolinks: true,
  }
  valid_options.each do |key, expected|
    if expected == false
      next unless options.key?(key)
    end
    actual = options[key]
    unless actual == expected
      fail Rails::Generators::Error, "Unsupported option: #{key}=#{actual}\n\nYou must run with --skip-listen --skip-spring --skip-turbolinks"
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

def gemfile_requirement(name)
  @original_gemfile ||= IO.read("Gemfile")
  req = @original_gemfile[/gem\s+['"]#{name}['"]\s*(,[><~= \t\d\.\w'"]*)?.*$/, 1]
  req && req.gsub("'", %(")).strip.sub(/^,\s*"/, ', "')
end

apply_template!

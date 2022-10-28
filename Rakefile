require 'bundler/setup'
$:.unshift File.expand_path('lib', __dir__)

# rake spec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) { |t| t.verbose = false }
task default: :spec

# rake console
task :console do
  require 'pry'
  ARGV.clear
  Pry.start
end

# frozen_string_literal: true

source 'http://rubygems.org'

ruby '3.2.2'

# bundler 2.5.7 does not work with rbenv
# Example:
# bundle show cocoapods outputs:
# ~/.local/share/gem/ruby/3.2.0/gems/cocoapods-1.15.0)
# And it should be
# ~/.rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/gems/cocoapods-1.15.0
gem 'bundler', '2.4.22'
gem 'cocoapods', '1.15.0'
gem 'fastlane', '2.220.0'
gem 'nokogiri', '1.16.3' # manually adding x86_64-darwin in .lock
gem 'simctl', '1.6.10'
gem 'xcodeproj', '1.24.0'

group :development do
  gem 'parallel', '1.24.0'
  gem 'rubocop', '1.62.1'
  gem 'rubocop-daemon', '0.3.2'
  gem 'rubocop-performance', '1.21.0'
  gem 'rubocop-require_tools', '0.1.2'
  gem 'rubocop-rspec', '2.29.1'
  gem 'solargraph', '0.50.0'
  gem 'yard', '0.9.36'

  # :test
  gem 'factory_bot', '6.4.6'
  gem 'fuubar', '2.5.1'
  gem 'rspec', '3.13.0'
end

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)

# frozen_string_literal: true

source 'http://rubygems.org'

group :xcode do
  gem 'cocoapods'
end

group :fastlane do
  gem 'fastlane'
  gem 'simctl'
  gem 'xcodeproj'
  gem 'parallel'

  plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
  eval_gemfile(plugins_path) if File.exist?(plugins_path)
end

group :code do
  gem 'rubocop'
  gem 'rubocop-daemon'
  gem 'rubocop-performance'
  gem 'rubocop-require_tools'
  gem 'rubocop-rspec'
  gem 'rubocop-factory_bot'
  gem 'solargraph'
  gem 'yard'
end

group :test do
  gem 'rspec'
  gem 'fuubar'
end

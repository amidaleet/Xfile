# frozen_string_literal: true

module SD_SPEC
  ROOT_DIR = ENV.fetch('GIT_ROOT', default: '').freeze
  FASTLANE_DIR = "#{ROOT_DIR}/fastlane".freeze
  SH_TOOLS_DIR = "#{ROOT_DIR}/tools/sh".freeze

  IOS_SIMULATOR_DEVICE_TYPE = 'iPhone 14'
  IOS_SIMULATOR_RUNTIME_VERSION = '17.2'
  IOS_SDK_VERSION = '17.2'

  MM_MESSAGE_MAX_LENGTH = 16_000

  def self.require_all
    masks = ['helpers/*.rb', 'products/**/*.rb']
    files = []
    masks.each do |m|
      files += Dir["#{FASTLANE_DIR}/#{m}"]
    end

    banned_words = ['_spec.rb', 'Fastfile', '_mock.rb']

    files.filter! do |e|
      has_banned = false
      banned_words.each do |w|
        if e.include?(w)
          has_banned = true
          break
        end
      end
      !has_banned
    end

    files.each { |file| require file }
  end
end

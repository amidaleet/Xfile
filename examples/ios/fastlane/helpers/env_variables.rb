# frozen_string_literal: true

require 'yaml'

class SD_ENV
  TRUTHY_VALUES = %w[t true yes y 1].freeze
  FALSEY_VALUES = %w[f false n no 0].freeze

  def self.is_dry_mode
    to_boolean(ENV.fetch('SD_DRY_RUN', false))
  end

  def self.is_verbose
    to_boolean(ENV.fetch('VERBOSE', false))
  end

  class InvalidValueForBooleanCasting < StandardError; end

  def self.to_boolean(value)
    return true if TRUTHY_VALUES.include?(value.to_s)
    return false if FALSEY_VALUES.include?(value.to_s)

    # You can even raise an exception if there's an invalid value
    raise InvalidValueForBooleanCasting
  end

  private_class_method :to_boolean
end

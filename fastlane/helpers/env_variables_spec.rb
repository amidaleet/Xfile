# frozen_string_literal: true

require 'fastlane'
require 'factory_bot'
require_relative '../sd_specs'
require_relative 'env_variables'

describe SD_ENV do
  before do
    ENV["SD_DRY_RUN"] = nil
    ENV["VERBOSE"] = nil
  end

  context 'when flag is set and it is bool' do
    before do
      ENV["SD_DRY_RUN"] = 'true'
      ENV["VERBOSE"] = 'true'
    end

    it do
      expect(SD_ENV.is_dry_mode).to eq(true)
      expect(SD_ENV.is_verbose).to eq(true)
    end
  end

  context 'when flag is set and it is number' do
    before do
      ENV["SD_DRY_RUN"] = '1'
      ENV["VERBOSE"] = '1'
    end

    it do
      expect(SD_ENV.is_dry_mode).to eq(true)
      expect(SD_ENV.is_verbose).to eq(true)
    end
  end

  context 'when flag is not set' do
    it do
      expect(SD_ENV.is_dry_mode).to eq(false)
      expect(SD_ENV.is_verbose).to eq(false)
    end
  end

  context 'when flag is set but it is not boolean' do
    before do
      ENV["SD_DRY_RUN"] = 'foo'
      ENV["VERBOSE"] = 'foo'
    end

    it do
      expect do
        SD_ENV.is_dry_mode
      end.to raise_error(SD_ENV::InvalidValueForBooleanCasting)
      expect do
        SD_ENV.is_verbose
      end.to raise_error(SD_ENV::InvalidValueForBooleanCasting)
    end
  end
end

require 'fastlane'
require 'simctl'
require_relative '../sd_specs'

desc 'Erase all iOS Simulators'
lane :remove_ios_simulators do
  UI.message "🧹  Will remove all iOS Simulators"

  sh('xcrun simctl delete all')

  UI.message "🗑️  Removed all iOS Simulators"
end

desc 'Add iOS Simulator for testing Xcode'
lane :add_ios_simulator_for_tests do
  name = 'Tests-Host'

  SimctlHelper.create_device(
    SD_SPEC::IOS_SIMULATOR_RUNTIME_VERSION,
    SD_SPEC::IOS_SIMULATOR_DEVICE_TYPE,
    name
  )

  UI.message "✅  Added iOS Simulator for tests run to your Xcode, name: #{name}"
end

desc 'Run iOS simulator and call passed block (replaces simctl Action from fastlane-plugin-simctl)'
lane :execute_with_simulator_ready do |options|
  # Original plugin code is outdated and depends on too old simctl
  name = options.fetch(:name)
  block = options.fetch(:block)

  SimctlHelper.execute_with_simulator_ready(
    block,
    SD_SPEC::IOS_SIMULATOR_RUNTIME_VERSION,
    SD_SPEC::IOS_SIMULATOR_DEVICE_TYPE,
    name
  )
end

module SimctlHelper
  def self.execute_with_simulator_ready(block, runtime, type, name)
    device = create_device(runtime, type, name)
    UI.message("🪄 Simulator device created!")
    UI.message("Simulator launchctl path = #{device.path.launchctl}")
    device.boot
    device.wait(180) do |d|
      UI.message("⏰ Waiting for simulator `#{d.name}` to be ready")
      d.state == :booted && d.ready?
    end
    print_preferences_plist(device, "after booting and waiting for ready")

    begin
      block.call(device)
    rescue StandardError => e
      throw(e)
    ensure
      delete_device(device)
    end
  end

  def self.create_device(runtime, type, name)
    runtime = if runtime.eql?('latest')
                SimCtl::Runtime.latest('ios')
              else
                SimCtl.runtime(version: runtime)
              end
    device_type = SimCtl.devicetype(name: type)
    device_name = name
    UI.message(
      "🚀 Starting simulator:\n" \
      "- runtime: `#{runtime.name}`\n" \
      "- type: `#{device_type.name}`\n" \
      "- name: `#{device_name}`"
    )
    device = SimCtl.reset_device(device_name, device_type, runtime)
    localize_device_to_ru(device)
    return device
  end

  def self.delete_device(device)
    if device.state != :shutdown
      device.shutdown
      device.kill
      device.wait do |d|
        UI.message("⏰ Waiting for simulator `#{d.name}` to be shutdown")
        d.state == :shutdown
      end
      print_preferences_plist(device, "after kill and shutdown")

    end
    UI.message("🧹 Deleting simulator `#{device.name}`")
    device.delete
  end

  def self.localize_device_to_ru(device)
    UI.message("🇷🇺 Set language and locale for `#{device.name}`")

    keyboards = [
      "ru_RU@sw=Russian;hw=Automatic",
      "en_US@sw=QWERTY;hw=Automatic",
      "emoji@sw=Emoji"
    ]

    plist = {
      AppleLanguagesDidMigrate: "20E247",
      AppleLanguagesSchemaVersion: 3000,
      AKLastIDMSEnvironment: 0,
      AKLastLocale: "ru_RU",
      AppleLocale: "ru_RU",
      AppleKeyboards: keyboards,
      AppleLanguages: ["ru-RU", "en-US"],
      ApplePasscodeKeyboards: keyboards,
      PKLogNotificationServiceResponsesKey: false,
      AddingEmojiKeybordHandled: true,
      AccessibilityEnabled: true,
      ApplicationAccessibilityEnabled: true
    }
    File.write(device.path.global_preferences_plist, Plist::Emit.dump(plist))
  end

  def self.print_preferences_plist(device, stage)
    puts(".GlobalPreferences.plist of: #{device.name} at stage: #{stage}")
    system("/usr/libexec/PlistBuddy -c \"Print\" #{device.path.global_preferences_plist}")
  end
end

# 🚨 Swizzling 🚨
#
# simctl had been refactored with Xcode 15 release.
#
# Simulator runtime file directory changed, moved to user level.
# Older Xcode path was located inside Xcode.app itself.
# New path includes dynamic part with iOS runtime "version" folder.
# So we need to parse simctl output to find current path.
#
# Xcode 15 path sample:
# /Library/Developer/CoreSimulator/Volumes/iOS_21A5326a/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.0.simruntime
#
# Xcode 14.3.1 path sample:
# /Applications/Xcode-14.3.1.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime
SimCtl::Xcode::Path.class_eval do
  def self.runtime_profiles
    if SimCtl::Xcode::Version.gte?('15.0')
      output = `xcrun simctl runtime list -v -j`
      json = JSON.parse(output)
      json.each do |r|
        runtime_json = r[1]
        next unless runtime_json['version'] == SD_SPEC::IOS_SIMULATOR_RUNTIME_VERSION

        simruntime_path = runtime_json['runtimeBundlePath']
        return File.dirname(simruntime_path)
      end
      raise "Not found #{SD_SPEC::IOS_SIMULATOR_RUNTIME_VERSION} in #{json}"
    elsif SimCtl::Xcode::Version.gte?('11.0')
      File.join(home, 'Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/')
    elsif SimCtl::Xcode::Version.gte?('9.0')
      File.join(home, 'Platforms/iPhoneOS.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/')
    else
      File.join(home, 'Platforms/iPhoneSimulator.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/')
    end
  end
end

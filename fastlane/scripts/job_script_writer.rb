require 'nokogiri'

source_file = "#{ENV.fetch('DX_JENKINS_JOB_SCRIPTS_DIR')}/#{ARGV[0]}.groovy"
config_file = "#{ENV.fetch('DX_JENKINS_JOB_CONFIGS_DIR')}/#{ARGV[1]}.xml"

xml_file = File.open(config_file, "r:UTF-8", &:read)
xml_obj = Nokogiri::XML(xml_file)

script = File.open(source_file, "r:UTF-8", &:read)
script_value = xml_obj.at_xpath("//script")
script_value.content = script

File.write(config_file, xml_obj, encoding: Encoding::UTF_8)

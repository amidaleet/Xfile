require 'nokogiri'

config_file = "#{ENV.fetch('DX_JENKINS_JOB_CONFIGS_DIR')}/#{ARGV[0]}.xml"

xml_file = File.open(config_file, "r:UTF-8", &:read)
xml_obj = Nokogiri::XML(xml_file)

puts xml_obj.xpath("//script").first.content

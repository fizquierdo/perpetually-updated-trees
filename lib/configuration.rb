
module PerpetualTreeConfiguration
  # Reader of the config file to run the example script
  class Configurator
    attr_reader :conf 
    def initialize(config_file)
      raise "config file #{config_file} not found" unless File.exist?(config_file)
      @conf_file = config_file
      @conf = {}
      self.read_config
    end

    def read_config
      File.open(@conf_file).readlines.each do |line|
        unless line =~ /^#/ or line =~/^\s*$/
          key, val = line.chomp.split(':').map{|s| s.strip}
          @conf[key] = val.split("#").first.strip
        end
      end
    end

  end
end

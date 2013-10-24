#!/usr/bin/env ruby
require 'fileutils'
load File.join File.dirname(__FILE__), 'install_logger.rb'
load File.join File.dirname(__FILE__), '..', 'lib', 'configuration.rb'

# Check input arguments: standalone or remote version?
valid_version = %w(standalone remote)
unless ARGV.size == 1 and valid_version.include? ARGV.first
  puts "Please specify if you are doing a standalone or remote installation"
  puts "usage: $#{$0} [standalone|remote]"
  exit
end
version = ARGV.first

# Check a valid Ruby version will be used
log = InstallLogger.new("pumper_dependencies.log")
log.info "Checking Ruby dependencies..."
if RUBY_VERSION.to_f >= 1.8
  log.info "Using Ruby #{RUBY_VERSION} ... OK"
else
  log.error "PUmPER requires Ruby version >= 1.8.7, please upgrade"
end

# Read the (default) user configuration for installation directories
config_file = File.join File.dirname(__FILE__), '..', 'config', 'local_config.yml'
opts = PerpetualTreeConfiguration::Configurator.new(config_file).conf
pumper_install_dir = File.expand_path opts["#{version}_install_dir"]
pumper_bin_dir     = File.expand_path opts["#{version}_bin_dir"] 
executables = %w(PUMPER  PUMPER_GENERATE)

# Install additional requirements for specified version
log.info "\nInstalling PUmPER (#{version} mode) in #{pumper_install_dir}"
if version == "standalone"
  install_raxml_locally(log) # raxml will run locally
else
  install_gems_remote(log)   # raxml will run in a cluster
  executables += %w(PUMPER_FINISH)
end

# Install the specified version accoding to the Rakefile instruccions (see Rakefile for details)
log.exec "rake install_#{version}", "PUmPER_#{version}_installation"

# Check if installation was OK
log.info "\nChecking for succesful installation of PUmPER ..."
executables.each do |pumper|
  if File.exist? File.join pumper_bin_dir, pumper
    log.info "#{pumper} is ready at #{pumper_bin_dir}"
  else
    log.error "#{pumper} could not be found in #{pumper_bin_dir}. Check configuration and Rakefile?"
  end
end
log.info "\nPUmPER (#{version} mode) has beed successfully installed. Have a look at the README to get started."
log.close

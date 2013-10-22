#!/usr/bin/env ruby
require 'fileutils'
load File.join File.dirname(__FILE__), 'install_logger.rb'

log = InstallLogger.new("pumper_dependencies.log")

log.info "Checking Ruby dependencies..."
# Assume a typicaly ruby installation is available (ruby 1.9.2 + gem) available
if defined?(Gem)
  log.info "RubyGems available ... OK"
else
  log.error "RubyGems is not installed. Please install from http://rubygems.org/pages/download"
end
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('1.9.2')
  log.info "Using Ruby #{RUBY_VERSION} ... OK"
else
  log.error "PUmPER requires Ruby >= 1.9.2, please upgrade your installation"
end

# Minimal gems required for standalone
required_gems = %w(rake trollop floatstats bio)
# Minimal gems required for remote
# required_gems += %w(net-scp net-ssh erb)

required_gems.each do |name| 
  begin 
    gem name
    log.info "Gem #{name} available ... OK"
  rescue Gem::LoadError
    cmd = "gem install --no-rdoc --no-ri #{name}"
    log.info "Gem #{name} is not installed ... Installing now..."
    log.info "Running: " + cmd
    log.error "Failed to install #{name}" unless system cmd
    log.info "Gem #{name} DONE"
  end
end
log.info "All Ruby dependencies... OK\n"

log.info "Checking Raxml dependencies..."
#log.exec("ruby errgen.rb", 'errgen') 
#
# parsimonator light std

log.close

#!/usr/bin/env ruby
require 'fileutils'
load File.join File.dirname(__FILE__), 'install_logger.rb'
load File.join File.dirname(__FILE__), '../lib/configuration.rb'

log = InstallLogger.new("pumper_dependencies.log")

log.info "Checking Ruby dependencies..."
# Assume a typicaly ruby installation is available (ruby 1.9.2 + gem) available
if defined?(Gem)
  log.info "RubyGems available ... OK"
else
  log.error "RubyGems is not installed. Please install from http://rubygems.org/pages/download"
end
#if Gem::Version.new(RUBY_VERSION.to_s) >= Gem::Version.new("1.9.2")
if RUBY_VERSION.to_f >= 1.9
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

# check wget, unzip exists
%w(wget unzip gcc).each do |tool|
  log.error "#{tool} could not be found. Automated installation aborted." if `which #{tool}`.empty?
end

binary_dir = File.expand_path(File.join File.dirname(__FILE__), '..', 'bin')
FileUtils.mkdir_p binary_dir 

# RAxML-like programs
programs = {
  :Parsimonator => {
    :versions => {
      :sse3          => {:binary => "parsimonator-SSE3", :ready => true,:comp => "Makefile.SSE3.gcc"} },
    :link => 'https://github.com/stamatak/Parsimonator-1.0.2/archive/master.zip',
    :folder => 'Parsimonator-1.0.2-master'}, 

  :RaxmlLight => {
     :versions => {
       :sse3          => {:binary => "raxmlLight",         :ready => true,:comp => "Makefile.SSE3.gcc"}, 
       :sse3_pthreads => {:binary => "raxmlLight-PTHREADS",:ready => true,:comp => "Makefile.SSE3.PTHREADS.gcc"}},
     :link => 'https://github.com/stamatak/RAxML-Light-1.0.5/archive/master.zip',
     :folder => 'RAxML-Light-1.0.5-master'},

  :Raxml => {
     :versions => {
       :sse3          => {:binary => "raxmlHPC-SSE3",         :ready => true,:comp => "Makefile.SSE3.gcc"}, 
       :sse3_pthreads => {:binary => "raxmlHPC-PTHREADS-SSE3",:ready => true,:comp => "Makefile.SSE3.PTHREADS.gcc"}},
     :link => 'https://github.com/stamatak/standard-RAxML/archive/master.zip',
     :folder => 'standard-RAxML-master'}
}
programs.each do |key, program|
  log.info "\nChecking #{key.to_s}..."
  installed = true
  #zipped = 'master.zip'
  zipped = 'master'
  folder = program[:folder]
  versions = program[:versions]
  versions.each do |key, v|
    if File.exist? File.join binary_dir, v[:binary] 
      log.info "#{key.to_s} available  ... OK"
    else
      v[:ready] = false
      installed = false
      log.info "#{key.to_s} will be installed in #{binary_dir} ..."
    end
  end
  unless installed
    log.error "Failed to download #{binary_name}" unless system "wget --no-check-certificate #{program[:link]}"
    log.error "Failed to unzip #{zipped}" unless system "unzip #{zipped}"
    Dir.chdir(folder) do
      versions.each do |key, v|
        unless v[:ready]
          log.error "Failed to compile #{v[:binary]}" unless system "make -f #{v[:comp]}"
          log.exec "rm *.o", "cleanup"
          log.exec "mv #{v[:binary]} #{binary_dir}", "move"
        end
      end
    end
    log.exec "rm #{zipped}", "cleanup"
    log.exec "rm -rf #{folder}", "cleanup"
  end
end
log.info "All RAxML-family dependencies... OK\n"

# Now install the PUmPER executables using the Rakefile and according to the configuration
opts = PerpetualTreeConfiguration::Configurator.new("config/local_config.yml").conf
pumper_install_dir = File.expand_path opts['install_dir']
pumper_bin_dir     = File.expand_path opts['bin_dir'] 

log.info "\nInstalling PUmPER in #{pumper_install_dir}"
log.exec "rake install", "PUmPER_installation"
%w(PUMPER  PUMPER_FINISH  PUMPER_GENERATE).each do |pumper|
  if File.exist? File.join pumper_bin_dir, pumper
    log.info "#{pumper} is ready at #{pumper_bin_dir}"
  else
    log.error "#{pumper} could not be found in #{pumper_bin_dir}. Check configuration and Rakefile?"
  end
end

log.info "\nPUmPER has beed successfully installed. Have a look at the README to get started."
log.close

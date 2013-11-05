#!/usr/bin/env ruby

require 'fileutils'

# This script automatically generates default config files to setup fast a perpetual project
class ProjectData
  attr_reader :name, :remote_config_file_name, :install_path, :pumper_version
  def initialize(name, best_bunch_size, parsimony_starting_size, initial_phylip = nil)
    @install_path="/opt/perpetualtree" # will be overwritten by Rakefile
    @name = name
    @best_bunch_size = best_bunch_size.to_i
    @parsimony_starting_size = parsimony_starting_size.to_i
    @initial_phylip = initial_phylip
    @remote_config_file_name = "remote_config.yml" #this one is assumed not to change for a group
    @best_bunch_name = "best_bunch.nw" 
    @iteration_results_name = "iteration_results.txt" 
    @iteration_log_name = "iterations.log" 
    # phlawd specific
    @phlawd_binary = "PHLAWD"
    @phlawd_autoupdate_info = "update_info"
    @pumper_version = "PUMPER_VERSION" # will be overwritten by Rakefile
  end
  def check_input
    # Make sure the initial phylip is there
    if @initial_phylip
      raise "Initial phylip ${initial_phylip} not found" unless File.exist?(@initial_phylip)
    end
    if @best_bunch_size > @parsimony_starting_size
      raise  ArgumentError, "Collection size #{@best_bunch_size} must be smaller or equal than parsimony starting size #{@parsimony_starting_size}"
    end
  end
  def print_config
    print_file(config_name, config_content)
  end
  def print_cron_job
    print_file("cron_#{@name}.rb", cron_content)
  end
  def print_starter_shell_script
    print_file "start_#{@name}.sh", starter_shell_script_content
  end

  private
  def config_name
    "pumper_config_#{@name}.yml"
  end
  def print_file(filename, content)
    File.open(filename, "w"){ |f| f.puts content}
  end

  def starter_shell_script_content
starter_shell_script = <<END_STARTER
#!/bin/sh
INITIAL_PHY=#{File.expand_path @initial_phylip}
PARSI=#{@parsimony_starting_size}
BUNCH=#{@best_bunch_size}
CONF=#{config_name}

PUMPER_PATH --name #{@name} --initial-phy $INITIAL_PHY --parsi-size $PARSI --bunch-size $BUNCH --config-file $CONF 
END_STARTER
  end

  def config_content
configfile_header = <<END_CONFIGFILE_HEADER
run_name: #{@name}
parsimony_starting_size: #{@parsimony_starting_size}
best_bunch_size: #{@best_bunch_size}

# Logs the alignment extensions and iteration restarts
updates_log: #{File.join project_dir, 'updates.log'}

# All the output will be written here (do not change)
experiments_file: #{File.expand_path 'pumper_experiments.yml'}
experiments_folder: #{experiments_dir}

# Generated alignments should be here
#{phlawd_configuration}

# Executable
put: /usr/bin/PUT

# Do not change
best_ml_folder_name: best_ml_trees
best_ml_bunch_name: #{@best_bunch_name}
iteration_results_name: #{@iteration_results_name}
iteration_log_name: #{@iteration_log_name}
END_CONFIGFILE_HEADER

configfile_tail = <<END_CONFIGFILE_TAIL
# Remote version
remote_config_file: #{File.expand_path @remote_config_file_name}
END_CONFIGFILE_TAIL

configfile  = configfile_header
configfile += configfile_tail if @pumper_version == 'remote'
configfile 
  end

  def cron_content
cron_str = <<END_CRON
#!/usr/bin/env ruby
$LOAD_PATH.unshift "#{@install_path}/lib"
require "configuration"
require "perpetual_updater"
require 'yaml'

# Find project according to run_name
config_file = File.expand_path(File.join File.dirname(__FILE__), "#{config_name}")

opts = PerpetualTreeConfiguration::Configurator.new(config_file).conf
all_experiments = YAML.load(File.read opts['experiments_file'])
experiment = all_experiments.find{|e| e[:name] == opts['run_name']}
project = PerpetualTreeUpdater::PerpetualProject.new(experiment, opts)

# Set up the parsimony multiplier for the next iteration 
project.parsi_size = #{parsimony_multiplier}

# Exit if required file structure is not found
%w(experiments_file experiments_folder remote_config_file).each do |req|
  unless File.exist?(opts[req]) 
    log = project.log
    log.error "Required  \#{req} not found" 
    exit
  end
end

# check if PHLAWD generated a new update
project.import_phlawd_updates("BUILD REQUIRED") # same key as in python autoupdate

# Launch a new iteration if new data is available
project.try_update
END_CRON
  end

  protected
  def phlawd_configuration
    if @initial_phylip
      wdir = File.expand_path("alignments")
      FileUtils.mkdir wdir
      phlawd_config_str = "phlawd_working_dir: #{wdir}"
    else
      # prepare some sample data
      basedir = "alignments"
      FileUtils.cp_r "#{@install_path}/testdata/#{basedir}", basedir
      phlawd_working_dir = File.expand_path(File.join basedir, "phlawd")
      phlawd_database_dir = File.expand_path(File.join basedir, "GenBank")
      phlawd_supermatrix_dir = File.expand_path(File.join basedir, "supermatrix")
      phlawd_config_str = <<END_PHLAWD_CONF
# Generic PHLAWD configuration
# Full path for PHLAWD v 3.3.
phlawd_binary: #{@phlawd_binary}
# Full path for database to be used 
phlawd_database_dir: #{phlawd_database_dir} 
# Full path for output of phlawd
phlawd_working_dir: #{phlawd_working_dir}
phlawd_supermatrix_dir: #{phlawd_supermatrix_dir}
phlawd_autoupdater: #{@install_path}/scripts/autoupdate_phlawd_db.py
phlawd_autoupdate_info: #{@phlawd_autoupdate_info}
END_PHLAWD_CONF
    end
    phlawd_config_str
  end
  def experiments_dir
    File.expand_path "experiments"
  end
  def project_dir
    File.join experiments_dir, @name
  end
  def parsimony_multiplier
    @parsimony_starting_size.to_i / @best_bunch_size.to_i
  end
end

usage = "#{$0} project_name best_bunch_size parsimony_starting_size [initial_phylip]
          \n For a fast example generating a pipeline run: 
          \n #{$0} pipeline "

if ARGV.size == 1 and ARGV.first == "pipeline"
  name = "pipeline_#{Time.now.to_i}"
  best_bunch_size = 1
  parsimony_starting_size = 3
  initial_phylip = nil
else
  raise usage unless ARGV.size == 4 or ARGV.size == 3
  name, best_bunch_size, parsimony_starting_size, initial_phylip = ARGV
end

p = ProjectData.new name, best_bunch_size, parsimony_starting_size, initial_phylip
p.check_input
p.print_config
p.print_cron_job

# Generate a starter script 
if initial_phylip
  # User provides the alignment
  p.print_starter_shell_script
else
  # Script where PHLAWD is used to generate the alignment
  FileUtils.copy "#{p.install_path}/scripts/run_perpetual_example.rb", Dir.pwd
end
# This one is useful to have  to analyze post results
FileUtils.copy "#{p.install_path}/scripts/summarize_results.rb", Dir.pwd

# Copy a default remote config script(required if we call this with remote)
if p.pumper_version == 'remote'
  if not File.exist?(p.remote_config_file_name)
    remote_config_file = "#{p.install_path}/templates/#{p.remote_config_file_name}"
    if File.exist? remote_config_file
      FileUtils.copy remote_config_file, Dir.pwd
    else
      puts "WARNING: Remote mode but could not find a remote config file in #{remote_config_file}"
    end
  end
end

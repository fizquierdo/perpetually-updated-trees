#!/usr/bin/env ruby

require 'fileutils'

# This script automatically generates default config files to setup fast a perpetual project

# Assumes:
#   the working dir should be the current directory
#   phlawd working dir is the one containing the initial phylip (updates expected there)


class ProjectData
  attr_reader :name, :remote_config_file_name, :install_path, :phlawd_name
  def initialize(name, best_bunch_size, parsimony_starting_size, initial_phylip = nil)
    @install_path="/opt/perpetualtree" # defined in the local config file
    @name = name
    @best_bunch_size = best_bunch_size.to_i
    @parsimony_starting_size = parsimony_starting_size.to_i
    @initial_phylip = initial_phylip
    @remote_config_file_name = "remote_config.yml" #this one is assumed not to change for a group
    @best_bunch_name = "best_bunch.nw" 
    @iteration_results_name = "iteration_results.txt" 
    # phlawd specific
    @phlawd_name = name
    @phlawd_name = name.split("_").first if name.include?("example")
    @phlawd_binary = "PHLAWD"
    @phlawd_autoupdate_info = "update_info"
    test_phlawd = "#{@install_path}/data"
    @phlawd_keep = "#{test_phlawd}/#{@phlawd_name}.keep"
    @phlawd_database = "#{test_phlawd}/pln.db" 
  end
  def check_input
    # Make sure the initial phylip is there
    if @initial_phylip
      raise "Initial phylip ${initial_phylip} not found" unless File.exist?(@initial_phylip)
      raise "Initial file does not start with project name #{@name}" unless File.basename(@initial_phylip).include?(@name)
end
    if @best_bunch_size > @parsimony_starting_size
      raise  ArgumentError, "Collection size #{@best_bunch_size} must be smaller or equal than parsimony startinng size #{@parsimony_starting_size}"
    end
  end
  def print_standalone_config
    print_file(standalone_config_name, standalone_config_content)
  end
  def print_cron_job
    print_file("cron_#{@name}.rb", cron_content)
  end
  def print_starter_shell_script
    print_file "start_#{@name}.sh", starter_shell_script_content
  end

  private
  def standalone_config_name
    "standalone_#{@name}.yml"
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
CONF=#{standalone_config_name}

# Execute standalone
PLANTER_PATH --name #{@name} --initial-phy $INITIAL_PHY --parsi-size $PARSI --bunch-size $BUNCH --standalone-config-file $CONF 

# Execute remotely
# PLANTER_PATH --name #{@name} --initial-phy $INITIAL_PHY --parsi-size $PARSI --bunch-size $BUNCH --standalone-config-file $CONF  --remote
END_STARTER
  end

  def standalone_config_content
standalone_config = <<END_STANDALONE
run_name: #{@name}
first_fasta_alignment: #{@phlawd_name}.FINAL.aln.rn
parsimony_starting_size: #{@parsimony_starting_size}
best_bunch_size: #{@best_bunch_size}
updates_log: #{File.join project_dir, 'updates.log'}

# All the output will be written here
experiments_file: #{File.expand_path 'experiments.yml'}
experiments_folder: #{experiments_dir}
remote_config_file: #{File.expand_path @remote_config_file_name}
# Uncomment to true if the remote configuration should be used for the searches
# remote: true 

# Full path for PHLAWD v 3.3.
phlawd_name: #{@phlawd_name}
phlawd_binary: #{@phlawd_binary}
# Full path for original seed sequences
phlawd_keep: #{@phlawd_keep}
# Full path for database to be used (if not generated)
phlawd_database: #{@phlawd_database} 
# phlawd_database: #{phlawd_working_dir}/../phlawd_db/#{File.basename @phlawd_database} # use this to generate a new one
# Full path for output of phlawd
phlawd_working_dir: #{phlawd_working_dir}
phlawd_autoupdater: #{@install_path}/scripts/autoupdate_phlawd_db.py
phlawd_autoupdate_info: #{@phlawd_autoupdate_info}

# Working dir for raxml pipeline
put: /usr/bin/PUT

# Do not change
best_ml_folder_name: best_ml_trees
best_ml_bunch_name: #{@best_bunch_name}
iteration_results_name: #{@iteration_results_name}
END_STANDALONE
  end

  def cron_content
cron_str = <<END_CRON
#!/usr/bin/env ruby
$LOAD_PATH.unshift "#{@install_path}/lib"
require "configuration"
require "perpetual_updater"
require 'yaml'

# Find project according to run_name
config_file = File.expand_path(File.join File.dirname(__FILE__), "#{standalone_config_name}")

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
project.import_phlawd_updates

# Launch a new iteration if new data is available
project.try_update
END_CRON
  end

  protected
  def phlawd_working_dir
    if @initial_phylip
      wdir = File.dirname(@initial_phylip)
    else
      wdir = "phlawd_alignments"
      FileUtils.mkdir_p wdir
    end
    File.expand_path wdir
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
          \n For a fast example generating a example run searching for rbcL
          \n #{$0} example "

if ARGV.size == 1 and ARGV.first == "example"
  name = "rbcL_example_#{Time.now.to_i}"
  best_bunch_size = 1
  parsimony_starting_size = 3
  initial_phylip = nil
else
  raise usage unless ARGV.size == 4 or ARGV.size == 3
  name, best_bunch_size, parsimony_starting_size, initial_phylip = ARGV
end

p = ProjectData.new name, best_bunch_size, parsimony_starting_size, initial_phylip
p.check_input
p.print_standalone_config
p.print_cron_job

# Starter script ?
if initial_phylip
  p.print_starter_shell_script
else
  FileUtils.copy "#{p.install_path}/scripts/run_perpetual_example.rb", Dir.pwd
end
# This one is useful to have 
FileUtils.copy "#{p.install_path}/scripts/summarize_results.rb", Dir.pwd

# Remote config script just copied (required if we call this with remote)
if not File.exist?(p.remote_config_file_name)
  remote_config_file = "#{p.install_path}/templates/#{p.remote_config_file_name}"
  if File.exist? remote_config_file
    FileUtils.copy remote_config_file, Dir.pwd
  else
    puts "#{remote_config_file} not found, please write the remote_config file or do not use remote mode (remote: false) in the standalone*.yml file"
  end
end


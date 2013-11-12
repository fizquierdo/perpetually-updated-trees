#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path("lib")

require 'trollop'
require 'fileutils'
require 'experiment'    
require 'pumper_helpers'    

version = 'standalone' # Override with Rakefile

if version == 'standalone'
  require 'starter'    
else
  require 'starter_remote'    
end

# helper functions
def read_yaml(yaml_file)
  # returns a hash 
  YAML.load(File.read yaml_file)
end
def find_iteration_id_and_last_dir(exp_name)
  e = ExperimentTable::Experiment.new(exp_name, File.expand_path(Dir.pwd))
  update_dir = File.join e.dirname("output"), e.last_bunch_dir
  iteration_id = update_dir.split("_").last.to_i 
  [iteration_id, update_dir]
end
def find_iteration_id(exp_name)
  find_iteration_id_and_last_dir(exp_name).first
end

expfile = File.expand_path "pumper_experiments.yml"

opts = Trollop::options do
  opt :show,       "show current state of experiments", :default => false
  opt :name,       "name of the experiment",            :type => :string
  opt :remove,     "name of the experiment to remove",  :type => :string
  opt :initial_phy,"initial alignment",                 :type => :string
  opt :update_phy, "update with a new update",          :type => :string
  opt :data_phy,   "type of data [DNA|PROT]",           :default => 'DNA'
  opt :partitions, "run partitioned search with file",  :type => :string
  opt :parsi_size, "Number of new parsimony trees",                    :default => 3
  opt :bunch_size, "Number of best ML trees at the end of iteration ", :default => 1
  opt :scratch,    "Ignore previous trees for --update-phy", :default => false 
  opt :num_threads,"number of threads",                   :type => :int
  opt :config_file,"Paths and configuration for the run", :type => :string

  puts
  puts "PUmPER - Phylogenies Updated PERpertually"
  puts
  puts "PUmPER running on #{version} mode".green
  puts
  puts "The initial iteration includes [parsi-size] topologies"
  puts "The initial iteration collects the best [bunch-size] topologies"
  puts
  puts "An update iteration includes [parsi-size] * [bunch-size] topologies"
  puts "(bunch_size referes to the previous iteration)"
  puts

end

# Verifiy data types
unless %w(DNA PROT).include? opts[:data_phy]
  puts "Specify a correct data type for the phylip alignment: DNA or PROT"
  exit
end

# load existing experiments
list = ExperimentTable::ExperimentList.new(expfile)

# p opts
# remove
if opts[:remove]
  list.remove(opts[:remove])
  FileUtils.rm_rf(File.join "experiments", opts[:remove])   
  exit
end
#if opts[:name]
#  if opts[:show]
#    list.show
#  else
#    puts "Run PUMPER -h to see options"
#  end
#  exit
#end

# check partition file really exists
if opts[:partitions]
  unless File.exist?(opts[:partitions])
    puts "specify an existing partition file"
    exit
  end
end

# starter
if opts[:initial_phy]
  unless File.exist?(opts[:initial_phy])
    puts "specify an existing initial phylip"
    exit
  end
  e = ExperimentTable::Experiment.new(opts[:name], File.expand_path(Dir.pwd))
  base_dir = File.join(e.dirname("output"), "bunch_0")
  puts "Starting initial iteration at #{pumper_path(base_dir)}"
  starter_opts = {:phylip => opts[:initial_phy], 
                  :partition_file => opts[:partitions],
                  :data_phy => opts[:data_phy],
                  :num_threads => opts[:num_threads],
                  :conf => read_yaml(opts[:config_file]),
                  :base_dir => base_dir,
                  :exp_name => opts[:name]}

  starter = TreeBunchStarter.new starter_opts
  if starter.ready? 
    if list.add(opts)
      best_lh = starter.start_iteration(:num_parsi_trees => opts[:parsi_size],
                                        :num_bestML_trees => opts[:bunch_size],
                                        :exp_name => opts[:name],
                                        :initial_iteration => true)
      list.update(opts[:name], "bestLH", best_lh)
    else
      puts "Could not set up PUmPER experiment (added failed)"
    end
  else
    puts "Could not set up PUmPER experiment (TreeBunchStarter not ready)"
  end
  exit
end

# updater
if opts[:update_phy]
  if not File.exist?(opts[:update_phy])
    puts "Specify an existing update phylip"
    exit
  end
  if list.name_available?(opts[:name])
    puts "PUmPER experiment cannot be updated"
    exit
  end
  e = ExperimentTable::Experiment.new(opts[:name], File.expand_path(Dir.pwd))
  iteration_id, last_dir = find_iteration_id_and_last_dir(opts[:name])
  if last_dir.nil?
    puts "No update possible, last bunch dir not found"
  else
    next_id = iteration_id.to_i + 1
    puts "Starting update #{next_id}"
    list.update(opts[:name], "u#{next_id.to_s}", "start #{pumper_time}")
    update_dir = File.join e.dirname("output"), "bunch_#{next_id.to_s}"
    updater = TreeBunchStarter.new(:phylip => opts[:update_phy], 
                                   :partition_file => opts[:partitions],
                                   :data_phy => opts[:data_phy],
                                   :prev_dir => last_dir,
                                   :base_dir => update_dir, 
                                   :update_id => next_id.to_i,
                                   :conf => read_yaml(opts[:config_file]),
                                   :num_threads => opts[:num_threads]) 
    if updater.ready? 
      best_lh = updater.start_iteration(:num_parsi_trees => opts[:parsi_size], 
                                        :num_bestML_trees => opts[:bunch_size],
                                        :exp_name => opts[:name],
                                        :initial_iteration => false,
                                        :scratch => opts[:scratch])
      update_info = best_lh
      update_info = ", done #{pumper_time}, bestLH: #{best_lh}" unless best_lh == "cluster"
      list.update(opts[:name], "u#{next_id}", update_info)
    end
  end
end
# show
list.show if opts[:show]

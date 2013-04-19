#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path("lib")

require 'trollop'
require 'fileutils'
require 'starter'    
require 'experiment'    
require 'pp'

#  Perpetually updated tree from the command line
# :num_parsi_trees : defaults to 3, will the the #of parsimony trees -N by parsimonator
# :num_bestML_trees : defaults to num_parsi_trees/2, will the the #of parsimony trees -N by parsimonator

expfile = File.expand_path "experiments.yml"

fakefiles_options = {
  '9999' => {:initial_seqs => 4000,
    :min_size_update => 1000,
    :max_size_update => 2000 
  },
  '10000' => {:initial_seqs => 4000,
    :min_size_update => 1000,
    :max_size_update => 2000 
  },
  '5000' => {:initial_seqs => 2000,
    :min_size_update => 300,
    :max_size_update => 700 
  },
  '1000' => {
  :initial_seqs => 500,
  :min_size_update => 60,
  :max_size_update => 120 
  },
  '20' => {
  :initial_seqs => 10,
  :min_size_update => 3,
  :max_size_update => 7
  }
}
DEFAULT_NUM_BEST_ML_TREES = 2
DEFAULT_NUM_NEW_PARSI_TREES = 3
opts = Trollop::options do
  opt :show, "show current state of experiments", :default => false
  opt :name, "name of the experiment", :default => ""
  opt :remove, "name of the experiment to remove", :default => ""

  opt :initial_phy, "initial alignment", :default => ""
  opt :update_phy, "update with a new update", :default => ""
  opt :partitions, "run partitioned search with file", :default => ""
  opt :parsi_size, "Number of new parsimony trees", :default => DEFAULT_NUM_NEW_PARSI_TREES
  opt :bunch_size, "Number of best ML trees at the end of iteration ", :default => DEFAULT_NUM_BEST_ML_TREES

  opt :remote, "Use cluster resources on remote machine", :default => false
  #opt :outliers, "Use an outliers file to re-adapt alignment and trees at last iter of given experiment", :default => ""

  opt :num_threads, "number of threads", :default => ""
  opt :fake_phy, "first generate fake updates from initial", :default => ""
  opt :search_std, "Conduct a standard RAxML search on given initial alignment", :default => false 
  opt :remote_config_file, "Paths and configuration for remote cluster", :default => "remote_config.yml" 
  opt :standalone_config_file, "Paths and configuration", :default => "standalone.yml" 

  puts
  puts "Perpetually updated Tree. Summery of cycles: "
  puts "First iteration includes parsi_size topologies"
  puts "First iteration collects the best bunch_size topologies"
  puts "Update iteration includes parsi_size * bunch_size_from_previous topologies"
  puts

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

list = ExperimentTable::ExperimentList.new(expfile)
# Process newick and phylip files so that outliers 
=begin
if not opts[:outliers].empty?
  if opts[:name].empty? 
    puts "Specify the name of the enperiment with --name"
  else
    outliers_file =  opts[:outliers]
    exp_name = opts[:name]
    iter = find_iteration_id(exp_name)
    puts "We will remove the outliers in #{outliers_file} of iteration #{iter} of experiment #{exp_name}"
    iteration_id, last_dir = find_iteration_id_and_last_dir(exp_name)
    updater = TreeBunchStarter.new(:base_dir => last_dir, 
                                   :update_id => iteration_id
                                   ) 
    taxa = File.open(outliers_file).readlines.map{|t| t.chomp!}
    updater.prune_taxa(taxa)
  end
  exit
end
=end

# remove
if not opts[:remove].empty?
  list.remove(opts[:remove])
  FileUtils.rm_rf(File.join "experiments", opts[:remove])   
  exit
end
if opts[:name].empty? 
  if opts[:show]
    list.show
  else
    puts "Specify a experiment name"
  end
  exit
end
# generator (this must cover all the functionality related to simulations)
if not opts[:fake_phy].empty? 
  ds_key = File.basename(opts[:fake_phy]).to_s
  if fakefiles_options.keys.include?(ds_key) and File.exist?(opts[:fake_phy])
    if list.add(opts) 
      puts "Generating the fake files..." 
      e = ExperimentTable::Experiment.new(opts[:name], File.expand_path(Dir.pwd))
      if e.setup_dirs
        expand_options = {:phylip => opts[:fake_phy], :updates_as_full_alignments => true}
        expand_options.merge! fakefiles_options[ds_key]
        e.expand_with_updates(expand_options)
      end
    end
  else
    puts "Unknwon test dataset"
  end
  exit
end
# check partition file really exists
if not opts[:partitions].empty? 
  if not File.exist?(opts[:partitions])
    puts "specify an existing partition file"
    exit
  end
end
# starter
if not opts[:initial_phy].empty? 
  if not File.exist?(opts[:initial_phy])
    puts "specify an existing initial phylip"
    exit
  end
  puts "starting a tree bunch"
  e = ExperimentTable::Experiment.new(opts[:name], File.expand_path(Dir.pwd))
  base_dir = File.join(e.dirname("output"), "bunch_0")
  cnf = YAML.load(File.read opts[:standalone_config_file])
  puts "starting a tree bunch #{base_dir}"
  starter = TreeBunchStarter.new(:phylip => opts[:initial_phy], 
                                 :partition_file => opts[:partitions],
                                 :num_threads => opts[:num_threads],
                                 :remote => opts[:remote],
                                 :remote_config_file => opts[:remote_config_file],
                                 :iteration_results_name => cnf['iteration_results_name'],
                                 :best_ml_folder_name => cnf['best_ml_folder_name'],
                                 :best_ml_bunch_name => cnf['best_ml_bunch_name'],
                                 :base_dir => base_dir,
                                 :exp_name => opts[:name]
                                )
  if starter.ready? 
    if list.add(opts)
      if opts[:search_std]
        best_lh = starter.search_std(opts[:bunch_size])
      else
        best_lh = starter.start_iteration(:num_parsi_trees => opts[:parsi_size],
                                          :num_bestML_trees => opts[:bunch_size],
                                          :exp_name => opts[:name],
                                          :initial_iteration => true
                                         )
      end
      list.update(opts[:name], "bestLH", best_lh)
    end
  end
  exit
end
# updater
if not opts[:update_phy].empty?  
  if not File.exist?(opts[:update_phy])
    puts "specify an existing update phylip"
    exit
  end
  if list.name_available?(opts[:name])
    puts "cannot be updated"
    exit
  end
  e = ExperimentTable::Experiment.new(opts[:name], File.expand_path(Dir.pwd))
  iteration_id, last_dir = find_iteration_id_and_last_dir(opts[:name])
  if last_dir.nil?
    puts "no update possible, last bunch dir not found"
  else
    next_id = iteration_id.to_i + 1
    puts "Starting update #{next_id}"
    list.update(opts[:name], "u#{next_id.to_s}", "start at #{Time.now}")
    update_dir = File.join e.dirname("output"), "bunch_#{next_id.to_s}"
    cnf = YAML.load(File.read opts[:standalone_config_file])
    updater = TreeBunchStarter.new(:phylip => opts[:update_phy], 
                                   :partition_file => opts[:partitions],
                                   :prev_dir => last_dir,
                                   :base_dir => update_dir, 
                                   :remote => opts[:remote],
                                   :update_id => next_id.to_i,
                                   :iteration_results_name => cnf['iteration_results_name'],
                                   :best_ml_folder_name => cnf['best_ml_folder_name'],
                                   :best_ml_bunch_name => cnf['best_ml_bunch_name'],
                                   :num_threads => opts[:num_threads]
                                   ) 

    if updater.ready? 
      best_lh = updater.start_iteration(:num_parsi_trees => opts[:parsi_size], 
                                        :num_bestML_trees => opts[:bunch_size],
                                        :exp_name => opts[:name],
                                        :initial_iteration => false
                                        )
      update_info = best_lh
      update_info = ",done at #{Time.now}, bestLH: #{best_lh}" unless best_lh == "cluster"
      list.update(opts[:name], "u#{next_id}", update_info)
    end
  end
end
# show
list.show if opts[:show]

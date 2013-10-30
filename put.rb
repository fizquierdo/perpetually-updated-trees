#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path("lib")

require 'trollop'
require 'fileutils'
require 'experiment'    

version = 'standalone'
if version == 'standalone'
  require 'starter'    
else
  require 'starter_remote'    
end

class String
  # colorization
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end
  def red
    colorize(31)
  end
  def green
    colorize(32)
  end
  def yellow
    colorize(33)
  end
  def pink
    colorize(35)
  end
end

  #  Perpetually updated tree from the command line
  # :num_parsi_trees : defaults to 3, will the the #of parsimony trees -N by parsimonator
  # :num_bestML_trees : defaults to num_parsi_trees/2, will the the #of parsimony trees -N by parsimonator

  expfile = File.expand_path "experiments.yml"

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

    #opt :remote, "Use cluster resources on remote machine", :default => false
    opt :num_threads, "number of threads", :default => ""
    opt :config_file, "Paths and configuration for the run", :default => "standalone.yml" 

    if version == 'standalone'
      opt :search_std, "Conduct a standard RAxML search on given initial alignment", :default => false 
    end
    #else
    #  opt :remote_config_file, "Paths and configuration for remote cluster", :default => "remote_config.yml" 
    #end

    puts
    puts "PUmPER on #{version} mode".green
    #  puts "Perpetually updated Tree. Summary of cycles: "
    #  puts "First iteration includes parsi_size topologies"
    #  puts "First iteration collects the best bunch_size topologies"
    #  puts "Update iteration includes parsi_size * bunch_size_from_previous topologies"
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
    e = ExperimentTable::Experiment.new(opts[:name], File.expand_path(Dir.pwd))
    base_dir = File.join(e.dirname("output"), "bunch_0")
    cnf = YAML.load(File.read opts[:config_file])
    p cnf
    puts "Starting initial iteration at #{base_dir}"
    starter_opts = {:phylip => opts[:initial_phy], 
      :partition_file => opts[:partitions],
      :num_threads => opts[:num_threads],
      :conf => cnf,
      #:iteration_results_name => cnf['iteration_results_name'],
      #:best_ml_folder_name => cnf['best_ml_folder_name'],
      #:best_ml_bunch_name => cnf['best_ml_bunch_name'],
      :base_dir => base_dir,
      :exp_name => opts[:name]}

    #if version == 'remote'
    #  starter_opts[:remote_config_file] = cnf['remote_config_file'] 
    #end

    starter = TreeBunchStarter.new starter_opts
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
      puts "No update possible, last bunch dir not found"
    else
      next_id = iteration_id.to_i + 1
      puts "Starting update #{next_id}"
      list.update(opts[:name], "u#{next_id.to_s}", "start at #{Time.now}")
      update_dir = File.join e.dirname("output"), "bunch_#{next_id.to_s}"
      cnf = YAML.load(File.read opts[:config_file])
      updater = TreeBunchStarter.new(:phylip => opts[:update_phy], 
                                     :partition_file => opts[:partitions],
                                     :prev_dir => last_dir,
                                     :base_dir => update_dir, 
                                     :update_id => next_id.to_i,
                                     :conf => cnf,
                                     #:iteration_results_name => cnf['iteration_results_name'],
                                     #:best_ml_folder_name => cnf['best_ml_folder_name'],
                                     #:best_ml_bunch_name => cnf['best_ml_bunch_name'],
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

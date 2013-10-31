#!/usr/bin/env ruby

# code import
require 'remote_job'
require 'rnewick'
require 'rphylip'
require 'perpetual_evaluation'

# gems
require 'logger'   
require 'net/ssh'
require 'net/scp'


class CycleController
  attr_reader :opts
  def initialize(opts, skip_phylip = false)
    @opts = opts
    unless skip_phylip
      @opts[:num_ptrees] ||= @opts[:num_parsi_trees]
      @numtaxa, @seqlen  = File.open(@opts[:phy]).readlines.first.split.map{|w| w.to_i}
    end
    # Read from an user-protected config file
    @conf = YAML.load_file(opts[:remote_config_file])
    # and a few helpers, this is all relative to the config above so we can fix it 
    @base_remote_dir = File.join @conf['remote_path'], "experiments/#{@opts[:exp_name]}/output/batch_#{@opts[:update_id]}"
    @opts[:alignment_remote_dir] = File.join @base_remote_dir, "alignments"
    @opts[:parsimony_remote_dir] = File.join @base_remote_dir, "parsimony_trees"
    @opts[:ml_remote_dir] = File.join @base_remote_dir, "ml_trees"
    @log ||= Logger.new @opts[:logpath]
    @log.info "Start cycle #{@opts[:update_id]} with options #{@opts.to_s}"
  end
  # NOTE these requirements are specific for our system, should be on a config file
  def parsimonator_requirements
    bytes_inner =  @numtaxa.to_f * @seqlen.to_f
    security_factor = 3.0
    required_MB = bytes_inner * security_factor * 1E-6
    required_MB = 16 unless required_MB > 16 
    @log.info "Parsimonator requirements in MB: #{required_MB}"
    required_MB.to_i
  end
  def raxmllight_requirements
    #(n-2) * m * ( 8 * 4 )
    bytes_inner =  @numtaxa.to_f * @seqlen.to_f  * 8 * 4
    security_factor = 1.3
    required_MB = bytes_inner * security_factor * 1E-6
    required_MB = 16 unless required_MB > 16 
    @log.info "Raxml Light requirements in MB: #{required_MB}"
    required_MB.to_i
  end

  def build_batch_options(dataset_filename, model_filename)
    raise "User Number of parsimony trees not set" unless @opts[:num_parsi_trees] > 0
    raise "Total Number of parsimony trees not set" unless @opts[:num_ptrees] > 0
    raise "Number of best ML trees not set" unless @opts[:num_bestML_trees] > 0
    # for parsimonator
    @opts[:parsimony_memory_requirements] = parsimonator_requirements
    @opts[:raxml_memory_requirements] = raxmllight_requirements
    dataset_full_path = File.join(@opts[:alignment_remote_dir], dataset_filename)
    @opts[:dataset_full_path] = dataset_full_path
    # for raxmllight / std-raxml
    if model_filename.nil? or model_filename.empty?
      @opts[:dataset_args] = " -s #{dataset_full_path} "
    else
      model_full_path = File.join(@opts[:alignment_remote_dir], model_filename)
      @opts[:dataset_args] = " -s #{dataset_full_path} -q #{model_full_path} "
    end
    @opts[:base_dir] = @conf['remote_path']
  end

  def run_as_batch_remote
    unless @conf['debug']
      # Prepare iteration data
      Net::SSH.start(@conf['remote_machine'], @conf['remote_user']) do |ssh|
        %w(alignment parsimony ml).map{|d| @opts["#{d}_remote_dir".to_sym]}.each do |remote_dir|
          @log.info "Creating remotely #{remote_dir}"
          @log.info ssh.exec!("mkdir -p #{remote_dir}")
        end
      end
      @log.info "Sending alignment #{@opts[:phy]} to remote machine #{@conf['remote_path']}\n----"
      Net::SCP.start(@conf['remote_machine'], @conf['remote_user']) do |scp|
        #send the alignment
        scp.upload! @opts[:phy], @opts[:alignment_remote_dir]
        scp.upload! @opts[:partition_file], @opts[:alignment_remote_dir] if File.exist? @opts[:partition_file]
        # send the starting trees
        unless @opts[:prev_trees_paths].nil?
          @opts[:prev_trees_paths].each do |path| 
            @log.info "Sending Tree #{path} to #{@opts[:parsimony_remote_dir]}"
            scp.upload! path, @opts[:parsimony_remote_dir]
          end
        end
      end
    end
    # Now use Jobber to populate a template and send it
    build_batch_options(File.basename(@opts[:phy]), File.basename(@opts[:partition_file])) 
    joberator = PerpetualRemoteJob::Jobber.new(@opts, @conf)
    joberator.run_pipeline 
    @log.info "\n\n Finished remote submission"
  end
end

class TreeBunchStarter 
  # Given an initial alignment, it creates a initial bunch of ML trees in bunch_0 dir
  # should log results
  attr_reader :bestML_trees_dir

  def initialize(opts)
    @phylip = opts[:phylip]
    @partition_file = opts[:partition_file]
    @base_dir = opts[:base_dir]
    @prev_dir = opts[:prev_dir]
    @update_id = opts[:update_id] || 0
    @num_threads = opts[:num_threads] || 0 
    # create dirs if required
    @alignment_dir = File.join @base_dir, "alignments"
    @parsimony_trees_dir = File.join @base_dir, "parsimony_trees"
    @parsimony_trees_out_dir = File.join @parsimony_trees_dir, "output"
    @ml_trees_dir = File.join @base_dir, "ml_trees"
    # the new phylip
    @phylip_updated = File.join @alignment_dir, "phy_#{@update_id.to_s}"
    # defaults , do we want defaults here?
    @num_parsi_trees = 4 
    @num_bestML_trees = @num_parsi_trees / 2 

    # if it is an update this info is already in opts[]
    @CAT_topology_bunch = File.join @ml_trees_dir, "CAT_topology_bunch.nw"
    @CAT_topology_bunch_order = File.join @ml_trees_dir, "CAT_topology_bunch_order.txt"

    cnf = opts[:conf] 
    @iteration_results_name = cnf['iteration_results_name']
    @bestML_trees_dir = File.join @base_dir, cnf['best_ml_folder_name']
    @bestML_bunch = File.join @bestML_trees_dir, cnf['best_ml_bunch_name']
    @prev_bestML_bunch = File.join @prev_dir, cnf['best_ml_folder_name'], cnf['best_ml_bunch_name'] unless @prev_dir.nil?
    # information on remote cluster
    @remote_config_file = cnf['remote_config_file'] 
    # logging locally
    #@logpath = File.join @base_dir, cnf['iteration_log_name']
    @logpath = cnf['iteration_log_name']
  end
  def logput(msg, error = false)
    @logger ||= Logger.new(@logpath)
    if error
      @logger.error msg
    else
      @logger.info msg
    end
    #puts msg
  end
  def ready?
    ready = true
    dirs = [@alignment_dir, @parsimony_trees_dir, @parsimony_trees_out_dir,@ml_trees_dir, @bestML_trees_dir]
    dirs.each do |d|
      if not File.exist?(d)
        FileUtils.mkdir_p d
        logput "Created #{d}"
      else
        logput "Exists #{d}"
        ready = false
      end
    end
    if @update_id == 0
      FileUtils.cp @phylip, @alignment_dir 
    else
      logput "Copying new update alignment (not expanding) from #{@phylip} to #{@phylip_updated}"
      FileUtils.cp @phylip, @phylip_updated 
    end
    FileUtils.cp @partition_file, @alignment_dir if @partition_file and File.exist? @partition_file
    ready
  end
  def start_iteration(opts)
    logput "starting iteration "
    check_options(opts)
    begin
      num_parsi_trees = opts[:num_parsi_trees] || @num_parsi_trees
      num_bestML_trees = opts[:num_bestML_trees] || @num_bestML_trees
      if opts[:initial_iteration]
        logput "Initial iteration, checking num_bestML_trees > num_parsi_trees\n----"
        phylip_dataset = @phylip
        num_iteration_trees = num_parsi_trees
        @update_id = 0
      else
        logput "update iteration, looking for parsimony start trees from previous bunch\n----"
        phylip_dataset = @phylip_updated
        raise "prev bunch not ready #{@prev_bestML_bunch}" unless File.exist?(@prev_bestML_bunch)
        last_best_bunch = PerpetualNewick::NewickFile.new(@prev_bestML_bunch)
        last_best_bunch.save_each_newick_as(File.join(@parsimony_trees_dir, 'prev_parsi_tree'), "nw") 
        prev_trees = Dir.entries(@parsimony_trees_dir).select{|f| f =~ /^prev_parsi_tree/}
        prev_trees_paths = prev_trees.map{|f| File.join @parsimony_trees_dir, f}
        num_iteration_trees = num_parsi_trees * prev_trees.size
        logput "#{prev_trees.size} initial trees available for this iteration, each will be input for #{num_parsi_trees} parsimonator runs, leading to #{num_iteration_trees} different parsimony starting trees for the new alignment"
      end
      if num_bestML_trees > num_iteration_trees 
        raise "#bestML trees (#{num_bestML_trees}) cant be higher than iteration number of trees #{num_iteration_trees}"
      end
      logput "Exp #{opts[:exp_name]}, your cluster will take care of this iteration no #{@update_id}"
      c = CycleController.new(:update_id => @update_id, 
                              :phy => phylip_dataset, 
                              :partition_file => @partition_file, 
                              :num_parsi_trees => num_parsi_trees, 
                              :num_ptrees => num_iteration_trees, 
                              :prev_trees_paths => prev_trees_paths, 
                              :num_bestML_trees => num_bestML_trees,
                              :base_dir => @base_dir,
                              :remote_config_file => @remote_config_file,
                              :logpath => @logpath,
                              :local_parsimony_dir => @parsimony_trees_dir, 
                              :local_ml_dir => @ml_trees_dir, 
                              :bestML_bunch => @bestML_bunch, 
                              :iteration_results_name => @iteration_results_name, 
                              :exp_name => opts[:exp_name]
                             )

      c.run_as_batch_remote # send prev_trees to remote machine!
      "cluster"
    rescue Exception => e
      logput(e, error = true)
      raise e
    end
  end
  private
  def check_options(opts)
    supported_opts = [:num_parsi_trees, :num_bestML_trees, :exp_name, :cycle_batch_script, :initial_iteration]
    opts.keys.each do |key|
      unless supported_opts.include?(key)
        logput "Option #{key} is unknwon"
      end
    end
  end
end

class IterationData
  attr_accessor :phylip_dataset, :num_trees, :prev_trees, :prev_trees_paths
  attr_reader :num_parsi_trees, :num_bestML_trees
  def initialize(opts, parsi_trees, bestML_trees)
    @num_parsi_trees = opts[:num_parsi_trees] || parsi_trees
    @num_bestML_trees = opts[:num_bestML_trees] || bestML_trees
  end
  def update_from_previous(prev_bestML_bunch, parsimony_trees_dir)
   raise "prev bunch not ready #{prev_bestML_bunch}" unless File.exist?(prev_bestML_bunch)
   last_best_bunch = PerpetualNewick::NewickFile.new(prev_bestML_bunch)
   last_best_bunch.save_each_newick_as(File.join(parsimony_trees_dir, 'prev_parsi_tree'), "nw") 

   @prev_trees       = Dir.entries(parsimony_trees_dir).select{|f| f =~ /^prev_parsi_tree/}
   @prev_trees_paths = @prev_trees.map{|f| File.join parsimony_trees_dir, f}
   @num_trees        = @num_parsi_trees * @prev_trees.size
  end
end

class TreeBunchStarterBase
  # Given an initial alignment, it creates a initial bunch of ML trees in bunch_0 dir
  # should log results
  attr_reader :bestML_trees_dir 

  def initialize(opts)
    @phylip = opts[:phylip]
    @data_phy = opts[:data_phy]
    @partition_file = opts[:partition_file] || ""
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
    lognew
    if error
      @logger.error msg
    else
      @logger.info msg
    end
    puts msg
  end
  def logputgreen(msg)
    lognew
    @logger.info msg
    puts msg.green
  end
  def ready?
    ready = true
    dirs = [@alignment_dir, @parsimony_trees_dir, @parsimony_trees_out_dir,@ml_trees_dir, @bestML_trees_dir]
    dirs.each do |d|
      if not File.exist?(d)
        FileUtils.mkdir_p d
        logput "Created " + pumper_path(d)
      else
        logput "Exists " + pumper_path(d)
        ready = false
      end
    end
    if @update_id == 0
      FileUtils.cp @phylip, @alignment_dir 
    else
      logput "Copying new update alignment (not expanding) from #{@phylip} to #{pumper_path @phylip_updated}"
      FileUtils.cp @phylip, @phylip_updated 
    end
    ready
  end
  private
  def lognew
    @logger ||= Logger.new(@logpath)
    @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
  end
  def check_options(opts)
    supported_opts = [:scratch, :num_parsi_trees, :num_bestML_trees, :exp_name, :cycle_batch_script, :initial_iteration]
    opts.keys.each do |key|
      unless supported_opts.include?(key)
        logput "Option #{key} is unknwon"
      end
    end
  end
  def prepare_iteration(opts)
      iteration_data = IterationData.new opts, @num_parsi_trees, @num_bestML_trees
      iteration_data.num_trees = iteration_data.num_parsi_trees
      if opts[:initial_iteration]
        @update_id = 0
        logputgreen "\nInitial iteration (number #{@update_id}):"
        iteration_data.phylip_dataset = @phylip
      else
        iteration_data.phylip_dataset = @phylip_updated
        if opts[:scratch]
          logputgreen "Update iteration (from scratch)"
          logput "Ignoring trees from previous bunch\n----"
        else
          logputgreen "Update iteration"
          logput "Looking for parsimony start trees from previous bunch\n----"
          iteration_data.update_from_previous @prev_bestML_bunch, @parsimony_trees_dir
          logput "#{iteration_data.prev_trees.size} initial trees available from previous iteration"
        end
      end
      logput "#{iteration_data.num_trees} ML trees will be generated from #{iteration_data.num_parsi_trees} new parsimony trees"
      if iteration_data.num_bestML_trees > iteration_data.num_trees 
        raise "#bestML trees (#{iteration_data.num_bestML_trees}) cant be higher than iteration number of trees #{iteration_data.num_trees}"
      end
      return iteration_data
  end
end

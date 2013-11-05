class TreeBunchStarterBase
  # Given an initial alignment, it creates a initial bunch of ML trees in bunch_0 dir
  # should log results
  attr_reader :bestML_trees_dir

  def initialize(opts)
    @phylip = opts[:phylip]
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
    @logger ||= Logger.new(@logpath)
    if error
      @logger.error msg
    else
      @logger.info msg
    end
    puts msg
  end
  def logputgreen(msg)
    @logger ||= Logger.new(@logpath)
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
      logput "Copying new update alignment (not expanding) from #{@phylip} to #{@phylip_updated}"
      FileUtils.cp @phylip, @phylip_updated 
    end
    ready
  end
end

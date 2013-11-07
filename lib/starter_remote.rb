#!/usr/bin/env ruby

# code import
require 'remote_job'
require 'rnewick'
require 'rphylip'
require 'perpetual_evaluation'
require 'starter_base'

# gems
require 'logger'   
require 'net/ssh'
require 'net/scp'


def mem_requirements_calculator(data_type)
  case data_type
  when 'DNA'
    states = 4
  when 'PROT'
    states = 20
  else
    raise "Unknown data type"
  end
end


class CycleController
  attr_reader :opts
  def initialize(opts)
    @opts = opts
    @opts[:num_ptrees] ||= @opts[:num_parsi_trees]
    @numtaxa, @seqlen  = File.open(@opts[:phy]).readlines.first.split.map{|w| w.to_i}
    # Read from an user-protected config file
    @conf = YAML.load_file(opts[:remote_config_file])
    # and a few helpers, this is all relative to the config above so we can fix it 
    @base_remote_dir = File.join @conf['remote_path'], "experiments/#{@opts[:exp_name]}/output/bunch_#{@opts[:update_id]}"
    @opts[:alignment_remote_dir] = File.join @base_remote_dir, "alignments"
    @opts[:parsimony_remote_dir] = File.join @base_remote_dir, "parsimony_trees"
    @opts[:ml_remote_dir] = File.join @base_remote_dir, "ml_trees"
    @log ||= Logger.new @opts[:logpath]
    @log.datetime_format = "%Y-%m-%d %H:%M:%S"
    loginfo "Start cycle #{@opts[:update_id]}"
    @log.info "Options #{@opts.to_s}"
  end

  def run_as_batch_remote
    unless @conf['debug']
      # Prepare iteration data
      Net::SSH.start(@conf['remote_machine'], @conf['remote_user']) do |ssh|
        %w(alignment parsimony ml).map{|d| @opts["#{d}_remote_dir".to_sym]}.each do |remote_dir|
          loginfo "Creating remotely #{remote_dir}"
          ssh.exec!("mkdir -p #{remote_dir}")
        end
      end
      loginfo "Sending alignment #{@opts[:phy]} to remote machine #{@conf['remote_path']}\n----"
      Net::SCP.start(@conf['remote_machine'], @conf['remote_user']) do |scp|
        #send the alignment
        scp.upload! @opts[:phy], @opts[:alignment_remote_dir]
        scp.upload! @opts[:partition_file], @opts[:alignment_remote_dir] if File.exist? @opts[:partition_file]
        # send the starting trees
        unless @opts[:prev_trees_paths].nil?
          @opts[:prev_trees_paths].each do |path| 
            loginfo "Sending Tree #{path} to #{@opts[:parsimony_remote_dir]}"
            scp.upload! path, @opts[:parsimony_remote_dir]
          end
        end
      end
    end
    # Now use Jobber to populate a template and send it
    build_batch_options(File.basename(@opts[:phy]), File.basename(@opts[:partition_file])) 
    joberator = PerpetualRemoteJob::Jobber.new(@opts, @conf)
    joberator.run_pipeline 
    loginfo "\n\n Finished remote submission, check status at #{@conf['mail_to']}"
  end

  private
  def parsimonator_requirements
    bytes_inner =  @numtaxa.to_f * @seqlen.to_f
    security_factor = 3.0
    required_MB = bytes_inner * security_factor * 1E-6
    required_MB = 16 unless required_MB > 16 
    loginfo "Parsimonator requirements in MB: #{required_MB}"
    required_MB.to_i
  end
  def raxmllight_requirements
    rate_method = 1 # 4 if we switch to GAMMA
    states = states_calculator(@opts[:data_type])
    #(n-2) * m * ( 8 * states * rate_method )
    bytes_inner =  @numtaxa.to_f * @seqlen.to_f  * 8 * rate_method * states
    security_factor = 1.3
    required_MB = bytes_inner * security_factor * 1E-6
    required_MB = 16 unless required_MB > 16 
    loginfo "Raxml Light requirements in MB: #{required_MB}"
    required_MB.to_i
  end
  def build_batch_options(dataset_filename, model_filename)
    raise "User Number of parsimony trees not set" unless @opts[:num_parsi_trees] > 0
    raise "Total Number of parsimony trees not set" unless @opts[:num_ptrees] > 0
    raise "Number of best ML trees not set" unless @opts[:num_bestML_trees] > 0
    # for parsimonator
    loginfo "Computing requirements"
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
  def loginfo(msg)
    @log.info msg
    puts msg
  end
end

class TreeBunchStarter < TreeBunchStarterBase
  def initialize(opts)
    super(opts)
  end
  def start_iteration(opts)
    logput "Preparing new iteration... "
    check_options(opts)
    begin
      iteration_data = prepare_iteration(opts)
      logputgreen "****** Start iteration number #{@update_id} ********"
      logput "Experiment #{opts[:exp_name]}, iteration no #{@update_id} will be run according to #{@remote_config_file}"
      c = CycleController.new(:update_id => @update_id, 
                              :phy =>              iteration_data.phylip_dataset, 
                              :num_parsi_trees =>  iteration_data.num_parsi_trees, 
                              :num_ptrees =>       iteration_data.num_trees, 
                              :prev_trees_paths => iteration_data.prev_trees_paths, 
                              :num_bestML_trees => iteration_data.num_bestML_trees,
                              :data_phy =>         @data_phy, 
                              :partition_file => @partition_file, 
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
end

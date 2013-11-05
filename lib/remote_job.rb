#!/usr/bin/env ruby
require 'erb'
require 'perpetual_evaluation'

module  PerpetualRemoteJob
class Jobber
  def initialize(opts, conf)
    @conf = conf 
    @opts = opts
    @log ||= Logger.new opts[:logpath] 
    @log.datetime_format = "%Y-%m-%d %H:%M:%S"
    begin
      setup_cluster
      calculate_distribution
      raise "No folder for templates" if @conf['templatedir'].nil? or not File.exist?(@conf['templatedir'])
    rescue Exception => exception 
      @log.error exception
      raise exception
    end
  end
  # send and sumbmit jobs (code transcribed from raxml_batch_cycle.sh)
  def run_pipeline
    loginfo "Running pipeline....#{@num_parsimony_batches} parsimony batches "
    # create the submitter
    i = 0
    while i <= @num_parsimony_batches 
      # Each parsimony batch runs in a different node
      if i == @num_parsimony_batches  
        @opts[:num_pars_runs] = @num_runs_extra
      else
        @opts[:num_pars_runs] = @opts[:max_runs_node]
      end
      loginfo "Start Batch #{i}/#{@num_parsimony_batches}, #{@opts[:num_pars_runs]} parsimony runs/ramllight scripts"

      #build and submit parsimonator script
      i_formatted = "%03d" % i 
      loginfo "run identifier: " +  i_formatted.to_s
      submitter_script = create_submitter_script(i_formatted)
      build_and_submit_parsimony_script(i, i_formatted, submitter_script)
      #build and send a raxmllight job for each parsimony tree
      @opts[:num_pars_runs].times do |j|
        k = i * @opts[:max_runs_node] + j
        build_and_send_raxmllight_script(k, i_formatted, submitter_script)
      end
      i +=1
    end
    loginfo "Done with raxml-light..."
    # the line below was used for sge submissions
    #build_and_submit_collector_script(i_formatted, "raxmllight_#{@opts[:exp_name]}_\\*")
    loginfo "Submission pipeline finished, jobs should be running "
    titlestr = "Project #{@opts[:exp_name]}, Iteration #{@opts[:update_id]}"
    content = "Submited from wooster at #{Time.now}\n\n Setup\n #{@opts.to_s} \n\n Conf\n #{@conf.to_s}"
    mailer = PerpetualTreeEvaluation::Mailer.new(:mail_to => @conf['mail_to'], 
                                             :title => titlestr, 
                                             :content_file => @opts[:logpath])
    mailer.send_mail
  end

  protected
  def calculate_distribution
    loginfo "Compute distribution for a total number of #{@opts[:num_ptrees]} topologies"
    cores_per_node = @opts[:cores_per_node]
    mem_per_node = @opts[:mem_per_node]
    # Maximum number of parsimonator runs / node
    max_runs_node = mem_per_node.to_i / @opts[:parsimony_memory_requirements].to_i
    max_runs_node = cores_per_node if max_runs_node > cores_per_node
    # Number of batch scripts 
    @num_parsimony_batches = @opts[:num_ptrees] / max_runs_node
    @num_runs_extra = @opts[:num_ptrees] % max_runs_node
    if @num_runs_extra == 0 
      @num_parsimony_batches -= 1
      @num_runs_extra = max_runs_node
    end
    @opts[:max_runs_node] = max_runs_node
    # Determine if MPI is needed
    if @opts[:raxml_memory_requirements] > mem_per_node 
      @opts[:num_nodes] = @opts[:raxml_memory_requirements] / mem_per_node + 1
      @opts[:num_tasks] = @opts[:num_nodes] * cores_per_node 
      loginfo "raxmlLight-MPI will be turned on #{@opts[:num_nodes]} using #{@opts[:num_tasks]}"
    else 
      @opts[:num_threads] = cores_per_node
      @opts[:num_nodes] = 1
      @opts[:num_tasks] = 1 * cores_per_node 
    end
    loginfo "Total number of trees in the iteration (number of independent light searches) #{@opts[:num_ptrees]}"
    loginfo "Num batches (each batch runs in one node) #{@num_parsimony_batches}"
  end
  def send_and_submit(remote_script_dir, local_script, holdstr = nil)
    send_job(remote_script_dir, local_script)
    submit_job(remote_script_dir, local_script, holdstr)
  end
  def send_job(remote_script_dir, local_script)
    scriptname = File.basename local_script
    loginfo "Sending #{scriptname}" 
    if @conf['debug']
      loginfo File.open(local_script).readlines{|l| loginfo l}
      loginfo ""
    else
      tries = 5
      begin
        Net::SCP.start(@conf['remote_machine'], @conf['remote_user']) do |scp|
          scp.upload! local_script, remote_script_dir
        end
      rescue Exception => exception 
        tries -= 1
        if tries > 0
          loginfo "Sending #{scriptname}, #{tries} attempts left"
          retry
        else
          @log.error "Failed to send #{scriptname}"
          @log.error exception
        end
      end
    end
  end
  def submit_job(remote_script_dir, local_script, holdstr = nil)
    subm_cmd = "sbatch"
    scriptname = File.basename local_script
    scriptname = " -hold_jid #{holdstr}" + " #{scriptname}" unless holdstr.nil?
    loginfo "Submitting #{scriptname}"
    tries = 5
    begin
      Net::SSH.start(@conf['remote_machine'], @conf['remote_user']) do |ssh|
        ssh_cmd = "cd #{remote_script_dir} && #{subm_cmd} #{scriptname}"
        res = ssh.exec! ssh_cmd
        loginfo "Run: #{ssh_cmd}\n" + res.to_s
      end
      loginfo "Submitted #{scriptname}"
    rescue Exception => exception 
      tries -= 1
      if tries > 0
        loginfo "Submitting #{scriptname}, #{tries} attempts left"
        retry
      else
        @log.error "Failed to submit #{scriptname}"
        @log.error exception
      end
    end
  end

  def build_and_submit_script(params, template_name, holdstr = nil)
    scriptname = build_script(params, template_name)
    send_and_submit(params[:remote_script_dir], scriptname, holdstr)
  end
  def build_and_send_script(params, template_name)
    scriptname = build_script(params, template_name)
    send_job(params[:remote_script_dir], scriptname)
  end

  def build_script(params, template_name)
    loginfo "Building/submitting #{params[:scriptname]}"
    loginfo "Starting tree(light): " + params[:tree_name] if template_name == "template_raxmllight.sge.erb"
    loginfo ""
    temp = ERB.new(File.new(File.join @conf['templatedir'], template_name).read)
    scriptname_fullpath = File.join params[:local_script_dir], params[:scriptname]
    File.open(scriptname_fullpath, "w"){|f| f.puts temp.result(binding)}
    scriptname_fullpath
  end

  def build_and_submit_parsimony_script(i, i_formatted, submitter_script)
    params = @opts
    subm = "slurm"
    # Prepare template missing data
    params[:exp_name_run_num] = @opts[:exp_name] + '_' + i_formatted
    params[:base] = i.to_i    # is used to generate the seed
    # config data
    params[:local_script_dir] = @opts[:local_parsimony_dir]
    params[:remote_script_dir] = @opts[:parsimony_remote_dir]
    params[:scriptname] = "parsimonator_#{params[:exp_name_run_num]}.#{subm}"
    # submitter data
    params[:light_submitter] = submitter_script
    # build
    build_and_submit_script(params, "template_parsimonate.#{subm}.erb")
  end
  def create_submitter_script(i_formatted)
    submitter_script = File.join @opts[:local_ml_dir], "submit_raxmllight_#{i_formatted}.sh"
    File.open(submitter_script, "w") do |f|
      f.puts "#!/bin/bash"
      f.chmod(0777)
    end
    submitter_script
  end

  def build_and_send_raxmllight_script(l, par_run, submitter_script)
    params = @opts
    subm = "slurm"
    l_formatted = "%03d" % l
    # Prepare template missing data
    parsi_run_name = @opts[:exp_name] + '_' + par_run # par_run is formatted
    l_run_name = @opts[:exp_name] + '_' + l_formatted 
    params[:exp_name_run_num] = parsi_run_name + '_' + l_formatted
    params[:binary] = @opts[:num_nodes] == 1 ? @opts[:raxmllight_pthreads] : @opts[:raxmllight_MPI]
    params[:tree_name] = "RAxML_parsimonyTree.#{l_run_name}"
    # config data
    params[:local_script_dir] = @opts[:local_ml_dir]
    params[:remote_script_dir] = @opts[:ml_remote_dir]
    params[:scriptname] = "raxmllight_#{params[:exp_name_run_num]}.#{subm}"
    # config data related to collection
    params[:bunch_id] = par_run
    # build script
    build_and_send_script(params, "template_raxmllight.#{subm}.erb")
    # Append the data to the submitter script
    File.open(submitter_script, "a") do |f|
      user = @conf['remote_user']
      machine = @conf['remote_machine']
      jobfile = params[:scriptname]
      path =  params[:remote_script_dir]
      f.puts "ssh #{user}@#{machine} \"cd #{path} && sbatch #{jobfile}\""
    end
  end

  def build_and_submit_collector_script(par_run_formatted, holdstr)
    params = @opts
    # Prepare template missing data
    params[:bunch_id] = par_run_formatted
    params[:exp_name_run_num] = [@opts[:exp_name], params[:bunch_id]].map{|n|n.to_s}.join('_')
    # config data
    params[:local_script_dir] = @opts[:local_ml_dir]
    params[:remote_script_dir] = @opts[:ml_remote_dir]
    params[:collector_script] = "collector_#{params[:exp_name_run_num]}.sge"
    params[:resub_script] = "post_raxmllight_#{params[:exp_name_run_num]}.rb"
    params[:holdstr] = holdstr
    params[:scriptname] = params[:collector_script]
  end

  def setup_cluster
    # This info must be read from the cluster config file or whatever logic
    loginfo "setup cluster"
    cluster_spec = @conf['cluster_spec'] || "default.config.yml"
    loginfo "cluster specs: #{cluster_spec}"
    cluster_config_file = File.join(@conf['templatedir'], cluster_spec)
    raise "No config file about cluster" unless File.exist?(cluster_config_file)
    cluster_conf = YAML.load_file(cluster_config_file)
    cluster_conf.each_pair do |key, value|
      @opts[key.to_sym]  = value
    end
  end
  def loginfo(msg)
    @log.info msg
    puts msg
  end
end
end

=begin
if __FILE__ == $0
  puts "Building jobs for perpetual tree in lonestar"
  # now some values for a small tree
  opts = {
    :parsimony_memory_requirements => 16,
    :raxml_memory_requirements => 16,
    :num_ptrees => 3,
    :exp_name => "fake_experiment"
  }
  planter = Jobber.new(opts)
  planter.calculate_distribution
  # now here we assume that the remote directory is available
  planter.run_pipeline
end
=end

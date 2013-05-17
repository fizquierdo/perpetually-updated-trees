#!/usr/bin/env ruby

require "starter"
require "experiment"
require 'fileutils'
require 'perpetual_utils'
require 'logger'
require 'phlawd' 

module PerpetualTreeUpdater

class PerpetualProject
  attr_reader :name
  attr_accessor :parsi_size, :bunch_size, :log
  def initialize(e, opts)
    @e = e
    @name = e[:name]
    @parsi_size = e[:parsi_size]
    @bunch_size = e[:bunch_size]
    @keys = e.keys 
    @opts = opts
    @log ||=  PerpetualTreeUtils::MultiLogger.new opts['updates_log']
  end

  
  def import_phlawd_updates(update_key)
    # Now this is all 
    @log.info "Try to import phlawd updates"

    # Let phlawd take care of this:
    phlawd = PerpetualPhlawd::Phlawd.new(@opts, @log)
    phlawd.print_instances
    fasta_alignments = phlawd.run_update(update_key, next_iteration)
    unless fasta_alignments.empty?
      @phlawd_fastas = PerpetualTreeUtils::FastaAlignmentCollection.new fasta_alignments, @log
      @phlawd_fastas.build_supermatrix(@opts, next_iteration)
    end
  end
  def try_update
    @log.info "Try update using #{`ruby -v`}"
    if File.exist?(last_folder)
      if last_iteration_finished?
        next_alignment = next_phlawd_alignment
        if next_alignment.empty?
          @log.info "NO UPDATE PROJECT #{@name} ITER #{next_iteration}"
        else
          @log.info "START UPDATE PROJECT #{@name} ITER #{next_iteration}"
          @log.info "Launch remote iteration #{next_iteration}"
          launch_update(next_alignment, log)
          @log.info "COMPLETED UPDATE PROJECT #{@name} ITER #{next_iteration}"
        end
      else
        @log.info "STILL RUNNING PROJECT #{@name} ITER #{last_iteration}"
      end
    else
      @log.error "Expected #{last_folder} does not exist"
    end
  end

  protected
  def last_iteration
    update_keys = @keys.select{|k| k =~ /^u[0-9]+$/}
    if update_keys.empty?
      iteration = 0
    else
      update_ids = update_keys.map{|k| k.gsub('u','').to_i}.sort
      iteration = update_ids.last
    end
    iteration.to_s
  end
  def next_iteration
    last_iteration.to_i + 1
  end
  def experiment_folder(iteration)
    File.expand_path File.join @opts['experiments_folder'], @name, "output","bunch_#{iteration}"
  end
  def last_folder
    experiment_folder(last_iteration)
  end
  def last_iteration_finished?
    finished = true
    best_ml_dir = File.join last_folder, @opts['best_ml_folder_name']
    ['iteration_results_name', 'best_ml_bunch_name'].each do |required|
      finished = false unless File.exist?(File.join best_ml_dir, @opts[required]) 
    end
    # Check that the label END_OF_ITERATION has been written
    if finished
      finished = false
      File.open(File.join best_ml_dir, @opts['iteration_results_name']).each_line do |l|
        finished = true if l =~ /END_OF_ITERATION/ 
      end
    end
    finished
  end
  def used_alignments
    used = []
    used << @e[:initial_phy] if @keys.include?(:initial_phy)
    update_phy_keys = @keys.select{|k| k =~ /^u[0-9]+_phy$/}
    update_phy_keys.each{|k| used << @e[k] }
    used
  end
  def next_phlawd_alignment
    next_alignment = ""
    wdir = File.join @opts['phlawd_supermatrix_dir'], "iter_#{next_iteration}"
    if File.exist? wdir
      alignments = Dir.entries(wdir).select{|f| f =~ /^#{@name}.+\.phy$/}
      candidates = alignments - used_alignments.map{|u| File.basename u}
      next_alignment = candidates.sort.first unless candidates.empty?
    end
    next_alignment 
  end
  def launch_update(alignment, log)
    # check if the partition file exists (assumes it is .model) 
    wdir = File.join @opts['phlawd_supermatrix_dir'], "iter_#{next_iteration}"
    partition_file = File.join(wdir, alignment.gsub("\.phy", "\.model"))
    partition_file = "" unless File.exist? partition_file
    list = ExperimentTable::ExperimentList.new(@opts['experiments_file'])
    @log.info "Create an instance of the cycle starter"
    updater = TreeBunchStarter.new(:phylip => File.join(wdir, alignment),
                                   :partition_file => partition_file,
                                   :prev_dir => last_folder,
                                   :base_dir => experiment_folder(next_iteration.to_s),
                                   :remote_config_file => @opts['remote_config_file'],
                                   :remote => @opts['remote'],
                                   :update_id => next_iteration.to_i,
                                   :num_threads => @opts[:num_threads],
                                   :iteration_results_name => @opts['iteration_results_name'],
                                   :best_ml_folder_name => @opts['best_ml_folder_name'],
                                   :best_ml_bunch_name => @opts['best_ml_bunch_name']
                                  )
    if updater.ready?
      best_lh = updater.start_iteration(:num_parsi_trees => @parsi_size,
                                        :num_bestML_trees => @bunch_size,
                                        :exp_name => @name,
                                        :initial_iteration => false
                                        )
      update_info = best_lh             
      update_info = ",done at #{Time.now}, bestLH: #{best_lh}" unless best_lh == "cluster"
      list.update(@name, "u#{next_iteration}", update_info)
      list.update(@name, "u#{next_iteration}_phy", alignment)
    else
      @log.info "Update Iteration is not ready. This iteration already exists?"
    end
  end
end

end

#!/usr/bin/env ruby


# code import
require 'rraxml'
require 'rnewick'
require 'rphylip'
require 'perpetual_evaluation'
#require 'perpetual_utils'
require 'starter_base'

# gems
require 'logger'   

class TreeBunchStarter < TreeBunchStarterBase
  def initialize(opts)
    super(opts)
  end
  def start_iteration(opts)
    logput "Preparing new iteration..."
    check_options(opts)
    begin
      iteration_data = prepare_iteration(opts)
      logputgreen "****** Start iteration number #{@update_id} ********"
      logputgreen "\nStep 1 of 2 : Compute #{iteration_data.num_parsi_trees} Parsimony starting trees\n----"
      if opts[:initial_iteration] or opts[:scratch]
        generate_parsimony_trees iteration_data.num_parsi_trees
        parsimony_trees_dir = @parsimony_trees_dir
      else
        update_parsimony_trees iteration_data
        parsimony_trees_dir = @parsimony_trees_out_dir
      end
      logputgreen "\nStep 2 of 2 : Compute #{iteration_data.num_trees} ML trees and select the #{iteration_data.num_bestML_trees} best\n----"
      best_lh = generate_ML_trees(parsimony_trees_dir, iteration_data, @partition_file)
      logput "Bunch of #{iteration_data.num_bestML_trees} best ML trees ready at #{pumper_path @bestML_bunch}\n----"
      logputgreen "****** Finished iteration no #{@update_id} ********"
      best_lh
    rescue Exception => e
      logput(e.to_s, error = true)
      raise e
    end
  end

  protected
  def raxmlSearcherFactory(opts, num_threads)
     bin_path = opts[:binary_path] || File.expand_path(File.join(File.dirname(__FILE__),"../bin"))
     opts.merge!({:num_threads => num_threads}) if num_threads.to_i > 0
     if File.exist? File.join(bin_path, "examl")
       logputgreen "Using Examl to search tree space"
       searcher = PerpetualTreeMaker::RaxmlExaml.new(opts)
     elsif File.exist? File.join(bin_path, "raxmlLight")
       opts.merge!(:flags => " -D ") # Use the RF convergence criterion
       logputgreen "Using raxmlLight to search tree space"
       searcher = PerpetualTreeMaker::RaxmlLight.new(opts)
     else
       raise "Cannot find examl or raxml-Light in the system"
       searcher = nil
     end
     searcher 
  end
  private
  def generate_parsimony_trees(num_parsi_trees)
    logput "Preparing parsimony runs for #{num_parsi_trees} trees" 
    logput "Results stored in #{pumper_path(@parsimony_trees_dir)}" 
    num_parsi_trees.times do |i|
      #seed = i + 123  # this is arbitrary, could be a random number
      seed = pumper_random_seed
      parsimonator_opts = {
        :phylip => @phylip,
        :num_trees => 1,
        :seed => seed,
        :logger => @logger,
        :outdir => @parsimony_trees_dir,
        :stderr => File.join(@parsimony_trees_dir, "err_treeno#{i}"),
        :stdout => File.join(@parsimony_trees_dir, "info_treeno#{i}"),
        :name => "parsimony_initial_s#{seed}"
      }
      parsi = PerpetualTreeMaker::Parsimonator.new(parsimonator_opts)  
      logput "\nComputing parsimony tree #{i+1}/#{num_parsi_trees} for the initial iteration ..."
      parsi.run
    end
    logput "Done with parsimony trees of initial bunch"
  end
  def update_parsimony_trees(iteration_data)
    num_parsi_trees = iteration_data.num_parsi_trees 
    trees           = iteration_data.prev_trees 
    trees.each_with_index do |parsi_start_tree, i|
      logput "Starting new parsimony tree with #{parsi_start_tree} trees" 
      parsimonator_opts = {
        :phylip => @phylip_updated,
        :num_trees => num_parsi_trees,
        :seed => pumper_random_seed,
        :logger => @logger,
        :newick => File.join(@parsimony_trees_dir, parsi_start_tree),
        :outdir => @parsimony_trees_out_dir,
        :stderr => File.join(@parsimony_trees_out_dir, "err_#{parsi_start_tree}"),
        :stdout => File.join(@parsimony_trees_out_dir, "info_#{parsi_start_tree}"),
        :name => "u#{@update_id}_#{parsi_start_tree}"
      }
      parsi = PerpetualTreeMaker::Parsimonator.new(parsimonator_opts)  
      logput "Start computing parsimony trees of #{parsi_start_tree}, #{i+1} of #{trees.size}"
      parsi.run
      logput "Update run with options #{parsi.ops.to_s}"
      logput "Done with parsimony trees of #{parsi_start_tree}, #{i+1} of #{trees.size}"
    end 
  end
  def generate_ML_trees(starting_trees_dir, iteration_data, partition_file = nil)
    phylip           = iteration_data.phylip_dataset
    num_bestML_trees = iteration_data.num_bestML_trees
    unless partition_file.nil? or partition_file.empty?
      partition_file = File.expand_path(File.join(@alignment_dir, File.basename(partition_file)))
      raise "partition file #{partition_file} not found" unless File.exist? partition_file
    end
    logput "Preparing ML searches ..."
    starting_trees = Dir.entries(starting_trees_dir).select{|f| f =~ /^RAxML_parsimonyTree/}
    raise "no starting trees available" if starting_trees.nil? or starting_trees.size < 1
    logput "#{starting_trees.size} starting trees available"
    logput "ML search results in #{pumper_path @ml_trees_dir}"
    gamma_trees = []
    starting_trees.each_with_index do |parsimony_tree, i|
      # Run pipeline locally
      tree_id = parsimony_tree.split("parsimonyTree.").last
      search_opts = {
        :phylip => phylip,
        :partition_file => partition_file,
        :outdir => @ml_trees_dir,
        :logger => @logger,
        :starting_newick => File.join(starting_trees_dir, parsimony_tree),
        :stderr => File.join(@ml_trees_dir, "err#{tree_id}"),
        :stdout => File.join(@ml_trees_dir, "info#{tree_id}"),
        :name => "starting_tree_" + tree_id
      }
      r = self.raxmlSearcherFactory(search_opts, @num_threads)
      logput "\nConducting ML search (#{i+1}/#{starting_trees.size}) with PSR model from #{parsimony_tree}"
      r.run

      # Score under GAMMA and compute local support after finding the best NNI tree 
      nni_starting_tree =  File.join(r.outdir, r.resultfilename)
      logput "Scoring tree #{i+1} under GAMMA (#{File.basename nni_starting_tree}) "
      scorer_opts = {
        :phylip => phylip,
        :partition_file => partition_file,
        :outdir => @ml_trees_dir,
        :logger => @logger,
        :starting_newick => nni_starting_tree,
        :stderr => File.join(@ml_trees_dir, "err_score_#{tree_id}"),
        :stdout => File.join(@ml_trees_dir, "info_score_#{tree_id}"),
        :name => "SCORING_GAMMA_#{tree_id}"
      }
      scorer_opts.merge!({:num_threads => @num_threads}) if @num_threads.to_i > 0
      scorer = PerpetualTreeMaker::RaxmlGammaScorer.new(scorer_opts)
      scorer.run
      final_lh = scorer.finalLH(File.join scorer.outdir, "RAxML_info.#{scorer.name}")
      logput "Score for tree #{i+1}: #{final_lh} (RAxML_result.#{scorer.name})"
    end
    # Get the best trees
    iteration_args = [@bestML_bunch, num_bestML_trees, "", @update_id, @ml_trees_dir, @iteration_results_name]
    iteration = PerpetualTreeEvaluation::IterationFinisher.new iteration_args
    iteration_results = PerpetualTreeEvaluation::ProjectResults.new :info_files_dir => iteration.results_dir, 
      :best_set => num_bestML_trees,
      :expected_set => starting_trees.size
    logput "\nResulting trees ranked by LH:"
    @logger.info "#{iteration_results.lh_rank.to_s}"
    iteration_results.print_lh_rank(@logger)
    iteration_results.print_lh_rank
    iteration.add_best_trees(iteration_results.lh_rank)
    iteration.add_finish_label
    best_lh = iteration_results.lh_rank.first[:lh]
    logputgreen "\nBest LH: #{best_lh}"
    best_lh
  end
end

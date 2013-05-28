#!/usr/bin/env ruby
require 'erb'
require 'rnewick'


module  PerpetualTreeEvaluation

class ProjectResults
  attr_accessor :best_set, :expected_set, :info_files_dir
  def initialize(opts)  
   @info_files_dir = opts[:info_files_dir]
   @best_set = opts[:best_set] || 10
   @expected_set = opts[:expected_set].to_i || 30
  end

  # check if we have gathered all the trees we expected
  def has_collected_all_trees?
    # TODO should also check that the support files have been transferred
    @expected_set == lh_rank.size
  end
  # Rank info
  def lh_rank
    scoring_info_files.map{|i| i.tree_scoring_info}.sort!{|tree1, tree2| tree2[:lh]<=>tree1[:lh]}
  end
  def print_lh_rank
    lh_rank.each_with_index do |t, i|
      puts "Tree rank #{i+1}: LH #{t[:lh]} , tree is #{t[:topology_name]}" 
    end
  end
  # Likelihoods only
  def lhs
    lh_rank.map{|t| t[:lh].to_f}
  end
  def best_lhs
    raise "best set #{@best_set} is too large" if @best_set > lhs.size
    lhs.slice(0,@best_set)
  end
  # Running time for search
  def times
    timing_info_files.map{|i| i.total_search_time}
  end
  # Number of iterations per search
  def search_iterations
    number_of_iterations = []
    log_files.each do |f|
      number_of_iterations << File.open(info_path f).readlines.size
    end
    number_of_iterations 
  end

  private
  def info_path(filename)
    File.join @info_files_dir,filename
  end
  def map_to_info_file(files)
    files.map{|f| InfoFile.new(info_path f)}
  end
  def entries
    Dir.entries @info_files_dir
  end
  def timing_info_files
    # ignore the timing related to the SCORING info
    map_to_info_file entries.grep(/^RAxML_info/).delete_if{|f| f =~ /SCORING/}
  end
  def scoring_info_files
    map_to_info_file entries.grep(/info\.SCORING/)
  end
  def log_files
    entries.grep(/^RAxML_log/)
  end
end

class InfoFile
  def initialize(filename)
    @filename = filename
    @lines = File.open(filename).readlines
  end
  def total_search_time
    find_val('Overall accumulated Time') / 3600.0
  end
  def tree_scoring_info 
    name = @filename.split('info.').last.chomp
    {:lh => find_val("Final Likelihood of NNI-optimized tree:"), 
     :runtime => find_val("Total execution time:"), 
     :topology_name => name.gsub('SCORING_', ''),
     :support_topology => "RAxML_fastTreeSH_Support.#{name}"
    }
  end

  private
  def find_val(key)
    matches = @lines.grep /#{key}/
    raise "No match found for #{key} in #{File.basename @filename}"  if matches.size == 0
    raise "More than one LH found" unless matches.size == 1
    matches.first.split(':').last.chomp.to_f
  end
end

  class Mailer
    def initialize(opts)
      @mail_to = opts[:mail_to] || "fer.izquierdo@gmail.com"
      @title = opts[:title] || ""
      @content_file = opts[:content_file] 
    end
    def send_mail
      title = "[PERPETUAL_TREE] " + @title.to_s
      mailstr = " -s \"#{title}\" #{@mail_to}"
      system "mutt #{mailstr} < #{@content_file}"
    end
  end

class IterationFinisher
  attr_reader :update_id, :results_dir, :bestML_bunch, :mail_to, :name, :tree_search_bunch_size, :ml_remote_dir
  attr_accessor :log 
  def initialize(collector_args)
    @collector_args = collector_args
 
    # Expected arguments
    @bestML_bunch = collector_args[0]              #this file is absolute path,  will be created
    @num_bestML_trees = collector_args[1].to_i
    @mail_to = collector_args[2] || ""
    @update_id = collector_args[3].to_i || -1
    @results_dir = collector_args[4]
    @iteration_results_filename = collector_args[5]
    @name = collector_args[6]
    @tree_search_bunch_size = collector_args[7]
    @ml_remote_dir = collector_args[8]

    # The file where we write the results of the iteration
    @log = File.open(iteration_log_filename, "a+")
    @log.puts "These are the results for iteration #{@update_id} exp..."
    @log.puts "All trees scored, ranking by LH,  the id corresponds to the line number in the file\n"
    @log.puts "Iteration finisher called with args #{@collector_args.to_s}"
  end
  def add_best_trees(lh_rank)
    raise "Less trees available than collection size" unless @num_bestML_trees <= lh_rank.size
    File.open(@bestML_bunch, "w") do |f|
      lh_rank.slice(0, @num_bestML_trees).each_with_index do |t, i|
        # Add the string to the best bunch
        f.puts File.open(File.join @results_dir, t[:support_topology]).readlines.first.chomp
        @log.puts  "Tree rank #{i+1}: LH #{t[:lh]} Selected tree is #{t[:topology_name]}" 
      end
    end
  end
  def cleanup
    @log.close
  end

  def iteration_log_filename
    File.join(best_tree_dir, @iteration_results_filename)
  end

  def upload_best_tree
    #system "head -n 1 #{bestML_bunch} > #{best_tree}"
    best_tree = File.join best_tree_dir, "best_tree.newick"
    newick_bestML_bunch = PerpetualNewick::NewickFile.new(bestML_bunch)
    newick_bestML_bunch.newickStrings.first.save_as(best_tree)
    tree_url = upload_iplant_tree(best_tree, @update_id)
    @log.puts "Best topology available at #{tree_url}"
    tree_url
  end

  def add_finish_label
    @log.puts "END_OF_ITERATION Iteration #{@update_id} finished at #{Time.now}"
  end

  private
  def best_tree_dir
    File.dirname(@bestML_bunch)
  end
  def upload_iplant_tree(newick_file, name)
   # TODO this is only relevant for iplant, should not be here?
   tree_url = ""

   url = "http://portnoy.iplantcollaborative.org/parseTree"
   form_data = "newickData=@#{newick_file}"
   form_name = "name=#{name}" 
  
   info_file = File.join(File.basename newick_file, "upload_stdout.txt") 
   system "curl -i -F \"#{form_data}\" -F \"#{form_name}\" #{url} > #{info_file}"
  
   tree_url = File.open(info_file).readlines.last.chomp!
  end
  
end

end

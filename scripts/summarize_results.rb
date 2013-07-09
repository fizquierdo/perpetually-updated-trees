#!/usr/bin/env ruby

$LOAD_PATH.unshift "/home/Fernando/perpetualtree/github/perpetually-updated-trees/lib"
require 'rnewick'
require 'floatstats'
require 'perpetual_evaluation'

module Enumerable
  def to_floatstats
    "Avg #{self.average.r_to(2)}, std dev #{self.standard_deviation.r_to(2)} (#{self.size.to_s})"
  end
end

class RFreader
  def initialize(values)
    @values  = values
  end
  def rfvalues
    @values.map{|dist| dist.split.last.chomp.to_f}
  end
  def report
    "#{rfvalues.average.r_to(3)} (#{rfvalues.size})"
  end
end

# Script to summarize results of an  iteration 
wdir = File.expand_path Dir.pwd
# results_dir is just the base directory of the experiment:
results_dir = ARGV[0] # /opt/perpetualtree/examples/NNI_support/production/bio_rbcL/
raise "#{$0} results_dir name" unless ARGV.size == 1
raise " ML dir #{results_dir} not found" unless File.exist?(results_dir)

# Show the ranking 
r = PerpetualTreeEvaluation::ProjectResults.new :info_files_dir => results_dir, 
 						:best_set => 10,
 						:expected_set => 30
Dir.chdir(results_dir) do 
  Dir.glob("**/*").select{|f| f =~ /\/bunch_.+\/ml_trees$/}.sort.each do |d|
    next if d =~ /failed/
    r.info_files_dir = d
    puts "\nDir #{r.info_files_dir}"
    puts "WARNING: Not all #{r.expected_set} trees have been collected" unless r.has_collected_all_trees?
    puts "Likelihood: " + r.lhs.to_floatstats
    r.best_set = r.lhs.size if r.lhs.size < r.best_set
    puts "Likelihood: " + r.best_lhs.to_floatstats + "[best set]"
    # Now find the runtimes of the searches
    puts "Runtime(h): " + r.times.to_floatstats + ", Total sum #{r.times.sum.r_to(2)}"

    # Now report the stats of number of iteration from the log files
    puts "Search Iterations: " + r.search_iterations.to_floatstats 

    ## Now we manually do a RF-analysis (TODO refactor)

    # Generate bunch
    curdir = File.expand_path d
    bunchfile = File.join(wdir, "bunch.nw")
    f_bunch = File.open(bunchfile, "w")
 
    # if a true tree is available, it is the first in the bunch
    use_true_tree = false
    num_trees = r.lhs.size
    true_tree = File.join curdir, "..", "true_tree.nw"
    if File.exist?(true_tree)
      puts "Adding true tree as first in the bunch (id 0)"
      use_true_tree = true
      f_bunch.puts File.open(true_tree).readlines.first
    end

    # Add all the others
    r.lh_rank.each do |t|
      topo = File.join curdir, t[:support_topology]
      f_bunch.puts File.open(topo).readlines.first
    end
    f_bunch.close
    # Now we can compare topologically VS true tree computing the RF distance with raxml
    name = "tmpRF"
    system "raxmlHPC-SSE3 -n #{name} -m GTRCAT -f r -z #{bunchfile} > /dev/null"
    rf_file = "RAxML_RF-Distances.#{name}"
    lines = File.open(rf_file).readlines
    system "rm *.#{name}"
    if use_true_tree
      rf_distances_true = RFreader.new lines.slice(0, num_trees)
      rf_distances = RFreader.new lines.slice(num_trees, lines.size - num_trees)
      puts "Avg RF true: #{rf_distances_true.report}"
    else
      rf_distances = RFreader.new lines.slice(0, lines.size)
    end
    puts "Avg RF each other: #{rf_distances.report}"

    ## Now we add a support distr of the best tree
    best_tree = File.join curdir, "../best_ml_trees", "best_bunch.nw"
    if File.exist? best_tree
      best_newick = PerpetualNewick::NewickFile.new(best_tree).newickStrings[0]
      #PerpetualNewick::NewickFile.new(best_tree).newickStrings.each do |best_newick|
      support_values = best_newick.support_values
      num = support_values.size
      puts "#{num} SH-like local support values distribution (as descr. in phyml 3.0)"
      #support = Hash.new(0)
      #support_values.sort.each { |v| support[v] += 1 }
      #support.each {|k,v| puts "#{k}: #{v}"}
      support_hist = Hash.new(0)
      support_values.sort.each { |v| support_hist[v/10] += 1 }
      support_hist.each {|k,v| puts ">=#{k.to_i * 10}: #{v} (#{((v.to_f/num.to_f)*100).r_to(2)}%)"}
      sum_support = support_values.inject(:+)
      puts "Sum of all support: #{sum_support}, avg per node: #{(sum_support.to_f/num.to_f).r_to(2)}"
      #end
    end
  end
end


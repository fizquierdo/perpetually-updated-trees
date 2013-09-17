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


def support_distri(support_values)
  num = support_values.size
  #puts "#{num} SH-like local support values distribution (as descr. in phyml 3.0)"
  #support_hist = Hash.new(0)
  #support_values.sort.each { |v| support_hist[v/10] += 1 }
  #support_hist.each {|k,v| puts ">=#{k.to_i * 10}: #{v} (#{((v.to_f/num.to_f)*100).r_to(2)}%)"}
  sum_support = support_values.inject(:+)
  #puts "Sum of all support: #{sum_support}, avg per node: #{(sum_support.to_f/num.to_f).r_to(2)}"
  (sum_support.to_f/num.to_f).r_to(2)
end

treeno = 1
treedir = "post_processing"
treename = "RAxML_fastTreeSH_Support.partition_scoring_#{treeno}"
support_values = []
partition_support_values = []

## Now we add a support distr of the best tree
tree = File.join treedir, treename
if File.exist? tree
  newick = PerpetualNewick::NewickFile.new(tree).newickStrings[0]
  support_values = newick.support_values
  #p support_values.slice(0,10)
  puts "STD support    #{support_distri(support_values)}"
  #support_distri(support_values)
end

## Now we add a partition support distr of the best tree
treename = "RAxML_fastTree_perPartition_SH_Support.partition_scoring_#{treeno}"
tree = File.join treedir, treename
single_support = []
num_partitions = 3
if File.exist? tree
  newick = PerpetualNewick::NewickFile.new(tree).newickStrings[0]
  partition_support_values = newick.partition_support_values
  #p partition_support_values.slice(0,10)
  # draw the distribuition support for single partitions
  num_partitions.times do |i|
    support_vals = partition_support_values.map{|n| n.gsub("[","").gsub("]","").split(",")[i].to_i}
    #p support_vals.slice(0,10)
    #puts "PART #{i} support"
    #support_distri(support_vals)
    puts "PART #{i} support #{support_distri(support_vals)}"
  end
  # now classify the partition support
  num_partitions_supported = {"0" => 0}
  per_partition = {}
  num_partitions.times do |n|
    partno = n + 1
    num_partitions_supported[partno.to_s] = 0
    per_partition["part" + partno.to_s] = 0
  end
  partition_support_values.each do |node_support_val| 
    partitions_supported = 0
    partition_node_support = node_support_val.gsub("[","").gsub("]","").split(",").map{|n| n.to_i}
    partition_node_support.each_with_index do |sup, i|
      if sup > 0
        partitions_supported += 1 
        per_partition["part#{i+1}"] += 1
      end
    end
    num_partitions_supported[partitions_supported.to_s] += 1
  end
  puts "Number of support values: #{support_values.size}"
  puts "Distribution of number of partitions that support a node"
  p num_partitions_supported
  puts "how many nodes does each partition support?"
  p per_partition
end

raise "not name len" unless partition_support_values.size == support_values.size

#support_values.size.times do |i|
#  puts support_values[i].to_s + ": " + partition_support_values[i]
#end

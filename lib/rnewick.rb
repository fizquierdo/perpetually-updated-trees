#!/usr/bin/env ruby

=begin
def binary_available(name)
  available = false
  ENV['PATH'].split(':').each do |folder|
    available = true if File.exists?(File.join folder, name)
  end
  available
end
=end
module PerpetualNewick
  class NewickString
    attr_reader :str
    def initialize(str)
      @str=String.new(str)
    end
    def save_as(filename)
      File.open(filename, "w"){|f| f.puts @str}
    end
    def support_values
      @str.gsub("0.0;","").scan(/\[([0-9]+)\]/).map{|n| n[0].to_i}
    end
    def partition_support_values
      @str.gsub("0.0;","").scan(/\[[\d+\,]+\d+\]/)
    end
    def branch_lengths
      @str.gsub("0.0;","").scan(/:([0-9]+\.[0-9]+)/).map{|n| n[0].to_f}
    end
    def str_with_scaled_branch_lengths(factor)
      newt = @str.gsub(/:([0-9]+\.[0-9]+)/) do |bl|
        newval = bl.gsub(":","").to_f * factor
        ":" + "%.9f" % newval 
      end
      newt
    end
    def str_with_numeric_branch_lengths
      newt = @str.gsub(/:([0-9]+\.[0-9]+)e-([0-9]+)/) do |bl|
        newval = bl.gsub(":","").to_f  
        ":" + "%.9f" % newval 
      end
      newt
    end
    def treelength
      self.branch_lengths.inject(0){|acc,i| acc+i}
    end
    def rawtopology
      @str.gsub(/[0-9]+\.[0-9]+/,'').gsub(':','')
    end
    def taxanames
      self.rawtopology.gsub("(", " ").gsub(")", " ").gsub(",", " ").gsub(";", " ").strip.split
    end
    def numtaxa
      @str.count(",").to_i + 1
    end
    def clean
      newstr = @str.gsub('(,)',"").gsub('(,(','((').gsub('),)','))')
      newstr = newstr.gsub('(,)',"").gsub('(,(','((').gsub('),)','))')
      newstr.gsub(',)',")").gsub('(,','(').gsub("e-06","")
    end
  end

  class NewickFile
    attr_reader :newickStrings
    def initialize(filename)
      @newickStrings = File.open(filename).readlines.map{|line| NewickString.new(line)}
      @filename = filename 
    end
    def size
      @newickStrings.size
    end
    def save_each_newick_as(newfile_basename, ending)
      @newickStrings.each_with_index do |newick, i|
        File.open(newfile_basename + "_#{i}.#{ending}" , "w") do |f|
          f.puts newick.str
        end
      end
    end
  end
end

=begin
if __FILE__ == $0 then
  # test usage
  tree = NewickFile.new(tree_topology).newickStrings[0]
  puts tree.numtaxa
end
=end

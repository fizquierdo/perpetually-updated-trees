#!/usr/bin/env ruby

load 'lib/rphylip.rb'

# Take a bunch of files and concat them all
#
usage = "ruby #{$0} base_phy additional_phy ... "
raise "USAGE #{usage}" unless ARGV.size > 1
ARGV.each do |phy|
  raise "USAGE #{usage}" unless File.exist?(phy) 
end


s = MultiPartition::SpeciesPhylip.new(MultiPartition::Phylip.new ARGV.shift)
puts "First Partition"
s.print_partitions
ARGV.each do |phyfile|
  puts "processing #{phyfile}"
  s.concat_phylip(MultiPartition::Phylip.new phyfile)
  s.print_partitions
end
s.save


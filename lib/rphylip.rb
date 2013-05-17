#!/usr/bin/env ruby

module MultiPartition
  class Phylip  
    attr_accessor :numtaxa, :seqlen, :seqs, :filename
    def initialize(filename)
      raise "File #{filename} does not exist" unless File.exists?(filename)
      lines = File.open(filename).readlines
      @filename = filename
      @numtaxa, @seqlen = lines[0].split.map{|w| w.to_i}
      lines.delete_at(0)
      lines.delete_if{|l| l=~ /^\s+$/}
      @seqs = {}
      lines.each do |line|
        name, seq = line.chomp.split
        if taxa_names.include?(name)
          $stderr.puts "#{taxa_names.size} taxa names parsed"
          $stderr.puts "#{name} Taxon name already exists, skipping" 
          next
        end
        @seqs[name] = seq
      end
      raise "Parsed #{@seqs.size} expected ntaxa #{@numtaxa}" unless taxa_names.size == @numtaxa
    end
    def taxa_names
      @seqs.keys.sort
    end
  end

  class Partition
    def initialize(from, to, name)
      @from = from
      @to = to
      @name = File.basename(name)
    end
    def to_s
      "DNA, #{@name} = #{@from} - #{@to}"
    end
  end

  class SpeciesPhylip
    def initialize(first_phylip, log, name = "species")
      @base = first_phylip
      @name = name
      @partitions = []
      @partitions << Partition.new(1, @base.seqlen, @base.filename)
      @log = log
    end
    def concat_phylip(new_phylip)
      missing = (@base.taxa_names - new_phylip.taxa_names)
      new = (new_phylip.taxa_names - @base.taxa_names)
      total = (@base.taxa_names + new_phylip.taxa_names).uniq
      both = total - missing - new
      @log.info "merging phylip alignment with #{new_phylip}"
      @log.info "missing #{missing.size}"
      @log.info "new #{new.size}"
      @log.info "both #{both.size}"
      @log.info "total #{total.size}"
      raise "total taxa unexpected" unless total.size == both.size + missing.size + new.size
      # edit the sequences
      both.each{|taxon| @base.seqs[taxon] += new_phylip.seqs[taxon]}
      missing.each{|taxon| @base.seqs[taxon] += "-" * new_phylip.seqlen}
      new.each{|taxon| @base.seqs[taxon] = "-" * @base.seqlen + new_phylip.seqs[taxon]}
      # update the partitions
      from = @base.seqlen + 1 
      to =  @base.seqlen + new_phylip.seqlen
      @partitions << Partition.new(from, to, new_phylip.filename)
      # update the header
      @base.seqlen += new_phylip.seqlen
      @base.numtaxa = total.size 
      @base.filename = @name
    end
    def print_partitions
      @partitions.each{|p| @log.info p.to_s}
    end
    def save
      File.open("#{@name}.phy", "w+") do |f|
        f.puts "#{@base.numtaxa} #{@base.seqlen}"
        @base.seqs.each_pair do |taxon_name, seq|
          f.puts "#{taxon_name} #{seq}"
        end
      end
      File.open("#{@name}.model", "w+") do |f|
        @partitions.each{|p| f.puts p.to_s}
      end
    end
  end
end

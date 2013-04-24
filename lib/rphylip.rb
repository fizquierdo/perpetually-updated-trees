#!/usr/bin/env ruby

module PerpetualRandomHelpers
  def fisher_yates_shuffle(a)
    (a.size-1).downto(1) do |i|
      j = rand(i+1)
      a[i], a[j] = a[j], a[i] if i != j
    end
  end
  def pseudonormal(x,y)
    num = 0
    reps = 4
    reps.times do
      num += rand(y - x + 1) + x
    end
    num / reps
  end
end

module PerpetualPhylip
  # TODO cleanup, most of this was prototype-testing code
  class Phylip
    include PerpetualRandomHelpers
    attr_reader :numtaxa, :seqlen, :seqs
    def initialize(phylipfile)
      raise "File #{phylipfile} does not exist" unless File.exists?(phylipfile)
      @filename = phylipfile
      @seqs = File.open(phylipfile).readlines
      @numtaxa, @seqlen = @seqs[0].split.map{|w| w.to_i}
      @seqs.delete_at(0)
      @seqs.delete_if{|l| l=~ /^\s+$/}
      raise "wrong number of seqs,parsed #{@seqs.size} expected ntaxa #{@numtaxa}" unless @seqs.size == @numtaxa
    end
    def names
      ali_names = []
      @seqs.each do |seq|
        ali_names << seq.split.first.strip 
      end
      raise "unexpected #names" unless ali_names.size == @numtaxa
      ali_names
    end
    def generate_base_alignment(numseqs_base)
      seqs = @seqs[0...numseqs_base].select{|s| s.split.last.split(//).uniq.size > 1}
      basename = @filename + "_initial"
      puts "Saving base alignment as #{basename} with #{seqs.size} seqs"
      raise "too few seqs" unless seqs.size > 4
      self.save_seqs_as(seqs, basename)
    end
    def generate_update(seqs, update_filename)
      # remove from seqs single char stuff
      seqs = seqs.select{|s| s.split.last.split(//).uniq.size > 1}
      puts "Saving update alignment as #{update_filename} with #{seqs.size} seqs"
      raise "too few seqs" unless seqs.size > 4
      self.save_seqs_as(seqs, update_filename)
    end
    def subdivide(numseqs_base, num_subalignments)
      # Subdivides the present alignemnt in a file base.phy and num_subalignments (i) subi.phy 
      # iterarions generated are of equal size
      if numseqs_base.to_i + num_subalignments.to_i > @numtaxa then
        raise "Wrong input to subdivide phylip file"
      else
        fisher_yates_shuffle(@seqs)
        generate_base_alignment(numseqs_base)
        # Generaute pseudo-new subsets of sequences
        rest = @seqs[numseqs_base...@seqs.size]
        subset_size = rest.size / num_subalignments 
        update_sequences = [] 
        rest.each_slice(subset_size) do |subset|
          # Note the last slice may be shorter unless rest.size % num_subalignments == 0
          if update_sequences.size < num_subalignments
            update_sequences << subset # a new subset
          else
            update_sequences[num_subalignments - 1] += subset # appends to the last subset
          end
        end
        update_sequences.each_with_index do |seqs, i|
          generate_update(seqs, @filename + "_sequpdate_#{i}.phy")
        end
      end
      return update_sequences.size 
    end
    def subdivide_random(conf)
      numseqs_base = conf[:initial_seqs]
      raise "too many seqs" if numseqs_base > @numtaxa
      fisher_yates_shuffle(@seqs)
      generate_base_alignment(numseqs_base)
      n = numseqs_base
      i = 0 #iteration id
      srand(12345) # be deterministic
      while n < @seqs.size
        num_newseqs = pseudonormal(conf[:min_size_update], conf[:max_size_update])
        num_newseqs = @seqs.size - n if (@seqs.size - n - num_newseqs < conf[:min_size_update])
        if conf[:updates_as_full_alignments].nil? or not conf[:updates_as_full_alignments]
          start = n
        else
          start = 0
        end
        generate_update(@seqs[start...n+num_newseqs], @filename + "_sequpdate_#{i}.phy")
        n += num_newseqs 
        i += 1
      end
      i
    end
=begin
  def remove_taxa(taxa, pruned_phylip)
    puts "Original size #{@seqs.size}, after removal expect #{@seqs.size - taxa.size}"
    raise "empty list of taxa to prune" if not taxa or taxa.empty?
    taxa.each do |taxon|
      @seqs.delete_if{|l| l.split.first.strip == taxon}
    end
    self.save_as(pruned_phylip)
    puts "Final size #{@seqs.size} saved in #{pruned_phylip}"
  end
=end
    def save_as(newfile)
      self.save_seqs_as(@seqs, newfile)
    end
    def save_seqs_as(seqs, newfile)
      File.open(newfile, "w") do |f|
        f.puts "#{seqs.size} #{@seqlen}"
        seqs.each{|seq| f.puts seq}
      end
    end
    def expand_with(phylipfile)
      additional_phylip = Phylip.new(phylipfile)
      if additional_phylip.seqlen == self.seqlen then
        additional_phylip.seqs.each do |newseq|
          @seqs << newseq
          @numtaxa += 1
        end
      else
        raise "different sequence lengths for new #{phylipfile}, cannot be expanded"
      end
    end
    def extract_partition(from_pos, to_pos)
      @seqlen = to_pos - from_pos  + 1
      newseqs = []
      from = from_pos - 1
      to = to_pos - 1
      @seqs.each do |seq|
        name, info = seq.split
        newseqs << name + " " + info.slice!(from..to) 
      end
      @seqs = newseqs
      self.save_as(@filename + "_from#{from_pos}_to#{to_pos}")
    end
  end

end


# TODO refactor this so we use only one module
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
          puts "#{taxa_names.size} taxa names parsed"
          puts "#{name} Taxon name already exists, skipping" 
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
    def initialize(first_phylip, name = "species")
      @base = first_phylip
      @name = name
      @partitions = []
      @partitions << Partition.new(1, @base.seqlen, @base.filename)
    end
    def concat_phylip(new_phylip)
      missing = (@base.taxa_names - new_phylip.taxa_names)
      new = (new_phylip.taxa_names - @base.taxa_names)
      total = (@base.taxa_names + new_phylip.taxa_names).uniq
      both = total - missing - new
      puts "missing #{missing.size}"
      puts "new #{new.size}"
      puts "both #{both.size}"
      puts "total #{total.size}"
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
      @partitions.each{|p| puts p.to_s}
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

#!/usr/bin/env ruby
require 'fileutils'

module TreeCheck
  def check_fulltree
    newick_taxa = PerpetualNewick::NewickFile.new(@starting_newick).newickStrings[0].numtaxa
    alignment_taxa = MultiPartition::Phylip.new(@phylip).numtaxa
    if alignment_taxa != newick_taxa
      raise "Tree #{@starting_newick} includes #{newick_taxa} taxa, #{alignment_taxa} expected"
    end
  end
  def check_correctAlignment
    rexec = PerpetualTreeMaker::RaxmlAlignmentChecker.new(:phylip => @phylip)
    rexec.run
    lastline =  File.open(rexec.stdout).readlines.last.chomp.strip
    if lastline != "Alignment format can be read by RAxML"
      raise "File #{@phylip} does not seem to be a correct alignment"
      ret = false
    else
      FileUtils.rm_rf rexec.outdir
      ret = true
    end
  end
end

module PerpetualTreeMaker
  class Raxml
    attr_reader :stdout, :stderr, :infofile, :name, :outdir, :phylip, :binary, :ops
    def initialize(opts)
      raise "No alignment in #{opts[:phylip]}" if opts[:phylip].nil? or not File.exist?(opts[:phylip])
      @phylip = opts[:phylip]
      @name = opts[:name] || "RUN_NAME"
      @seed = opts[:seed] || "12345"
      @outdir = opts[:outdir] || "test/outdir/#{@name}"
      @stderr = opts[:stderr] || File.join(@outdir, 'stderr')
      @stdout = opts[:stdout] || File.join(@outdir, 'stdout')
      @binary = ""
      @binary_path = opts[:binary_path] || File.expand_path(File.join(File.dirname(__FILE__),"../bin"))
      @flags = opts[:flags] || ""
      @ops = "-s #{@phylip} -n #{@name} #{@flags}"
      @ops += " -q #{opts[:partition_file]} " unless opts[:partition_file].nil? or opts[:partition_file].empty? 
    end
    def before_run
      FileUtils.mkdir_p @outdir unless File.exist?(@outdir) 
      self.complete_call
    end
    def after_run
      @infofile = File.join Dir.pwd, "RAxML_info.#{@name}" 
      @outfiles = [@stdout, @stderr, @infofile]
      self.gather_outfiles
      @outfiles.each do |f| 
        unless f.nil? or not File.exist?(f)
          unless File.join(@outdir, File.basename(f)) == f
            FileUtils.move(f, @outdir) 
            #puts "#{f} available in #{@outdir}" unless f =~ /binaryCheckpoint/
            #puts File.basename f unless f =~ /binaryCheckpoint/
          end
        end
      end
    end
    def binary_available?
      available = false
      ENV['PATH'].split(':').each do |folder|
        available = true if File.exists?(File.join folder, @binary)
      end
      available
    end
    def run
      self.before_run
      #raise "#{@binary} not found" unless binary_available?
      #if not binary_available?
        # TODO check out how to do this with the correct path
        # use the compiled version from src
        @binary = File.join(@binary_path, @binary)
        raise "#{@binary} not found" unless File.exists?(@binary)
      #end
      # TODO write this to a log
      puts "#{@binary} #{@ops}" unless @ops =~ /RUN_NAME/ 
      system "(#{@binary} #{@ops} 2> #{@stderr}) > #{@stdout}"
      self.after_run
    end
    def salute
      puts "This is a RAxML instance"
    end
  end


  class Parsimonator < Raxml
    include TreeCheck
    attr_reader :seed, :num_trees, :newick
    def initialize(opts)
      super(opts)
      check_correctAlignment
      @num_trees = opts[:num_trees] || 1
      @newick = opts[:newick] || ""
      @binary = 'parsimonator-SSE3'
    end
    def complete_call
      @ops += " -N #{@num_trees} -p #{@seed}"
      unless @newick.empty? then
        raise "No newick starting tree?" unless File.exists?(@newick)
        @ops += " -t #{@newick}"
      end
    end
    def gather_outfiles
      @num_trees.times{|i| @outfiles <<  "RAxML_parsimonyTree.#{name}.#{i}"}
    end
  end
  class RaxmlLight < Raxml
    include TreeCheck
    attr_reader :starting_newick
    def initialize(opts)
      super(opts)
      check_correctAlignment
      if opts[:starting_newick].nil? or not File.exists?(opts[:starting_newick])
        raise "Raxml Light requires a starting tree" 
      end
      @starting_newick = opts[:starting_newick] 
      check_fulltree # makes sure the tree is comprenhensive in relation to the phylip file
      #@name = @starting_newick.split(".").last 
      if opts[:num_threads].nil? 
        @binary = 'raxmlLight'
        @num_threads = 0
      else
        @binary = 'raxmlLight-PTHREADS'
        @num_threads = opts[:num_threads].to_i
      end
    end
    def complete_call
      @ops += " -m GTRCAT -t #{@starting_newick} "
      @ops += " -T #{@num_threads} " if @num_threads > 0
    end
    def resultfilename
      "RAxML_result.#{@name}"
    end
    def logfilename
      "RAxML_log.#{@name}"
    end
    def gather_outfiles
      @outfiles += [self.resultfilename, self.logfilename]
      Dir.entries(Dir.pwd).select{|f| f=~ /^RAxML_binaryCheckpoint.#{@name}_/}.each{ |f| @outfiles << f}
        @outfiles
    end
  end
  class RaxmlGammaScorer < Raxml
    include TreeCheck
    def initialize(opts)
      super(opts)
      check_correctAlignment
      if opts[:starting_newick].nil? or not File.exists?(opts[:starting_newick])
        raise "Scorer requires a starting bunch of trees to score" 
      end
      @starting_newick = opts[:starting_newick]
      check_fulltree # makes sure the tree is comprenhensive in relation to the phylip file
      if opts[:num_threads].nil? 
        @binary = 'raxmlHPC-SSE3'
        @num_threads = 0
      else
        @binary = 'raxmlHPC-PTHREADS-SSE3'
        @num_threads = opts[:num_threads].to_i
      end
    end
    def complete_call
      @ops += " -m GTRGAMMA -t #{@starting_newick} -f J"
      @ops += " -T #{@num_threads} " if @num_threads > 0
    end
    def gather_outfiles
      @outfiles += ["RAxML_fastTree.#{@name}", "RAxML_fastTreeSH_Support.#{@name}"]
    end
    def finalLH(infofile)
      lines  = File.open(infofile).readlines.select{|l| l =~ /Final Likelihood/}
      if lines and lines.size == 1 
        lh = lines.first.chomp.split(":").last.to_f
      else
        lh = -1.0
      end
      lh.to_s
    end
  end
  class RaxmlAlignmentChecker < Raxml
    def initialize(phylipfile)
      super(phylipfile)
      @binary = 'raxmlHPC-SSE3'
    end
    def complete_call
      @ops += " -m GTRCAT -f c"
    end
    def gather_outfiles
    end
  end

  class RaxmlGammaSearch < Raxml
    include TreeCheck
    def initialize(opts)
      super(opts)
      check_correctAlignment
      @num_trees = opts[:num_gamma_trees] 
      if opts[:num_threads].nil? 
        @binary = 'raxmlHPC-SSE3'
        @num_threads = 0
      else
        @binary = 'raxmlHPC-PTHREADS-SSE3'
        @num_threads = opts[:num_threads].to_i
      end
    end
    def complete_call
      @ops += " -m GTRCAT -p #{@seed} -N #{@num_trees}"
      @ops += " -T #{@num_threads} " if @num_threads > 0
    end
    def gather_outfiles
      @outfiles += ["RAxML_bestTree.#{@name}"]
      other_files = ["result", "log", "parsimonyTree"]
      if @num_trees > 1
        @num_trees.times{|num| @outfiles += other_files.map{|n| "RAxML_" + n + ".#{@name}.RUN.#{num.to_s}"} }
      else
        @outfiles += other_files.map{|n| "RAxML_" + n + ".#{@name}"}
      end
    end
  end
end

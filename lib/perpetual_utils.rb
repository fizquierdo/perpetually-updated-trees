
require 'bio'
require 'rphylip'

module PerpetualTreeUtils

  # Some special log to show case the steps of the pipeline
  class MultiLogger
    def initialize(log_file_name, silent = false)
      @log ||= Logger.new log_file_name
      @log.datetime_format = "%Y-%m-%d %H:%M:%S"
      @log_file = log_file_name
      @silent = silent
    end
    def systemlog(cmd, header = "")
      @log.info "#{header}: Executing #{cmd}"
      puts "#{header}: Executing #{cmd}"
      system "#{cmd} | tee -a #{@log_file}"
    end
    def info(msg, header = "")
      @log.info "#{header}: #{msg}"
      puts "#{header}: #{msg}" unless @silent
    end
    def close
      @log.close
    end
  end




  # Converter Fasta2Phylip
  class Fasta
    def initialize(filename)
      @seqs = []
      @widths = []
      raise "File #{filename} does not exist" unless File.exist? filename
      ff = Bio::FlatFile.open(Bio::FastaFormat, filename)
      ff.each_entry do |fa|
        @seqs << fa.definition + " " + fa.naseq
        @widths << fa.nalen 
      end
    end
    def to_phylip(filename)
      # Ensure all seqs have the same width
      raise "Not all sequences have the same width" unless @widths.size > 0 and @widths.uniq.size == 1
      File.open(filename, "w") do |f|
        f.puts "#{@seqs.size} #{@widths.first.to_s}"
        @seqs.each{|s| f.puts s} 
      end
    end
  end
  
  class FastaAlignmentCollection
    attr_accessor :aln, :part
    def initialize(phlawd_iteration, log)
      @fasta_alignments = phlawd_iteration.fasta_alignments
      @taxa_names_files = phlawd_iteration.taxa_names_files
      @log = log
      @aln = ""
      @part = ""
    end
    def build_phylip_collection(iteration, archive = false)
      @phylip_alignments = @fasta_alignments.map do |fasta| 
        @log.info "Translating #{fasta} into phylip"
        phylip_name = fasta.to_s + ".phy"
        fasta_file = PerpetualTreeUtils::Fasta.new(fasta)
        fasta_file.to_phylip(phylip_name)
        #fasta_file.archive(iteration) if archive # TODO 
        phylip_name
      end
    end
    def build_supermatrix(opts, iteration)
      build_phylip_collection(iteration, archive = true)
      raise "No phylip alignment available" if @phylip_alignments.empty?
      wdir = opts['phlawd_supermatrix_dir']
      wdir = File.join wdir, "iter_#{iteration}"
      FileUtils.mkdir_p wdir 
      msa_name = opts['run_name'] + Time.now.to_i.to_s
      Dir.chdir(wdir) do
        # create the concatenated MSA
        first_phylip = MultiPartition::Phylip.new @phylip_alignments.shift
        @log.info "Building alignment called #{msa_name}"
        msa = MultiPartition::SpeciesPhylip.new(first_phylip, @log, msa_name)
        @phylip_alignments.each do |phylip_filename|
          @log.info "Adding #{phylip_filename}"
          msa.concat_phylip(MultiPartition::Phylip.new phylip_filename)
        end
        msa.save
        # Save the current gi files
        @taxa_names_files.each do |gi_file|
          if File.exist? gi_file
            FileUtils.cp gi_file, File.basename(gi_file)
          else
            @log.info "Expected #{gi_file} does not exist"
          end
        end
      end
      @aln = File.join wdir, "#{msa_name}.phy" 
      @part = File.join wdir,  "#{msa_name}.model"
    end
  end

end

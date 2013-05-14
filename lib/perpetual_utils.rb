
require 'bio'

module PerpetualTreeUtils

  # Some special log to show case the steps of the pipeline
  class MultiLogger
    def initialize(log_file_name)
      @log ||= Logger.new log_file_name
      @log.datetime_format = "%Y-%m-%d %H:%M:%S"
      @log_file = log_file_name
    end
    def systemlog(cmd, header = "")
      @log.info "#{header}: Executing #{cmd}"
      puts "#{header}: Executing #{cmd}"
      system "#{cmd} | tee -a #{@log_file}"
    end
    def info(msg, header = "")
      @log.info "#{header}: #{msg}"
      puts "#{header}: #{msg}"
    end
    def close
      @log.close
    end
  end


  # Instalation procedure for raxml
  class RaxmlInstaller
    attr_reader :tar_src
    def initialize(opts)
      @tar_src = opts[:src]
      @dest_dir = File.expand_path(opts[:dest]) 
      [@tar_src, @dest_dir].each do |f|
        raise "#{f} not found" unless File.exist?(f)
      end
    end
    def unpack_at
      puts "unpacking #{@tar_src}"
      system "tar xfz #{@tar_src}"
      @tar_src.split(".tar").first
    end
    def install(instruc)
      system "make -f #{instruc[:makefile]}"
      system "rm *.o"
      FileUtils.mv instruc[:binary], @dest_dir
      puts "\nInstalled #{instruc[:binary]} at #{@dest_dir}"
    end
  end
  class SrcInstaller
    def initialize(opts)
      @src_dir = opts[:src_dir] 
      @install_dir = opts[:install_dir] 
      @parsi_src = "stamatak-Parsimonator-1.0.2-43f5160.tar.gz"
      @light_src = "stamatak-RAxML-Light-1.0.5-674d62b.tar.gz" 
      @std_src = "stamatak-standard-RAxML-e0fd7e9.tar.gz"
      FileUtils.mkdir_p @install_dir 
    end
    def install_raxml
      Dir.chdir(@src_dir) do
        # Parsimonator 
        i = RaxmlInstaller.new(:src => @parsi_src, :dest => @install_dir)
        newdir = i.unpack_at
        Dir.chdir(newdir) do
          i.install(:makefile => "Makefile.SSE3.gcc", :binary => "parsimonator-SSE3", :dest => @install_dir) 
        end
        FileUtils.rm_rf newdir
        # Light 
        i = RaxmlInstaller.new(:src => @light_src, :dest => @install_dir)
        newdir = i.unpack_at
        Dir.chdir(newdir) do
          i.install(:makefile => "Makefile.SSE3.gcc", :binary => "raxmlLight", :dest => @install_dir) 
          i.install(:makefile => "Makefile.SSE3.PTHREADS.gcc", :binary => "raxmlLight-PTHREADS", :dest => @install_dir) 
        end
        FileUtils.rm_rf newdir
        # Standard
        i = RaxmlInstaller.new(:src => @std_src, :dest => @install_dir)
        newdir = i.unpack_at
        Dir.chdir(newdir) do
          i.install(:makefile => "Makefile.SSE3.gcc", :binary => "raxmlHPC-SSE3", :dest => @install_dir) 
          i.install(:makefile => "Makefile.SSE3.PTHREADS.gcc", :binary => "raxmlHPC-PTHREADS-SSE3", :dest => @install_dir) 
        end
        FileUtils.rm_rf newdir
      end
    end
  end


  # Converter Fasta2Phylip
  class Fasta
    def initialize(filename)
      @seqs = []
      @widths = []
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

end

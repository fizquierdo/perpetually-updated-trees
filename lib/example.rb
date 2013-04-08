
require 'bio'

module PerpetualTreeExample

  # Some special log to show case the steps of the pipeline
  class ExampleLogger
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

  # PHLAWD wrapper
  # NOTE_STEPHEN
  class Phlawd
    def initialize(opts, log)
      @log = log
      @PHLAWD = opts['phlawd_binary']
      @working_dir = opts['phlawd_working_dir']
      @keep_path = opts['phlawd_keep']
      @db_path = opts['phlawd_database']
      @phlawd_autoupdater = opts['phlawd_autoupdater']
      @run_name = opts['run_name'] || 'rbcL'
      @phlawd_name = opts['phlawd_name'] || 'rbcL'
      @phlawd_autoupdate_info = opts['phlawd_autoupdate_info'] || 'update_info'
      raise "File with sequence seeds #{@keep_path} not found" unless File.exist?(@keep_path)
      #raise "Database #{@db_path} not found" unless File.exist?(@db_path)
    end
    def setupdb
      # PHLAWD database (takes some time but, if required can be generated as)
      db_setup = <<END_OF_DB_SETUP
       db = pln.db
       division = pln
       download
END_OF_DB_SETUP
      # Database can then be generated as:
      db_setup_file = "db.setup"
      File.open(db_setup_file, "w"){|f| f.puts db_setup}
      system "(#{@PHLAWD} setupdb #{db_setup_file} > db_setup.log) 2> db_setup.err"
    end

    def run_initial
      phlawd_runfile_fullpath = phlawd_runfile_generate(update = false)
      # Now we are ready to run PHLAWD
      Dir.chdir(@working_dir) do 
        @log.systemlog("#{@PHLAWD} assemble #{phlawd_runfile_fullpath}", "PHLAWD STDOUT>>")
        @log.info("Done with PHLAWD", "<<PHLAWD STDOUT")
      end
      # And generate the update file
      phlawd_runfile_fullpath = phlawd_runfile_generate(update = true)
      # generate  also a script that can run the update
      dbdir = File.dirname @db_path
      dbname = File.basename @db_path
      phlawd_autoupdate_file =      File.join dbdir, "#{@phlawd_name}_autoupdate.sh"
      phlawd_update = "python #{@phlawd_autoupdater} #{@PHLAWD} #{@phlawd_name} #{dbname}.tmp #{dbname}"
      File.open(phlawd_autoupdate_file, "w") do |f| 
        f.puts "# Move to the working dir to rebuild the database"
	f.puts "cd #{dbdir}"
        f.puts "# Log the stdout from the previous attempt"
	f.puts "rm -rf taxdump.tar.*"
        f.puts "date >> #{@phlawd_autoupdate_info}.log"
        f.puts "cat #{@phlawd_autoupdate_info} >> #{@phlawd_autoupdate_info}.log"
        f.puts "# Edit accordingly and (optionally) call from a cronjob"
        f.puts "(#{phlawd_update} 2> update_err ) > #{@phlawd_autoupdate_info} &"
      end
    end
    private
	def phlawd_runfile_generate(update = false)
           # Starting data for PHLAWD,simple runfile that will create an alignment of 10 sequences
           if update
             label =  "updateDB" 
             wdir = File.dirname @db_path
           else
             label = ""
             wdir = @working_dir
           end
           
           phlawd_runfile = <<END_OF_PHLAWD_RUNFILE
             clade = Lonicera
             search = #{@phlawd_name}
             gene = #{@phlawd_name}
             mad =  0.05
             coverage = 0.2
             identity = 0.2
             db = #{@db_path}
             knownfile = #{@keep_path} 
             numthreads = 2
             #{label}
END_OF_PHLAWD_RUNFILE
           # Generate and copy the phlawd files to the working dir
           @log.info(phlawd_runfile, "PHLAWD RUNFILE: ")
           phlawd_runfile_fullpath = File.join wdir, "#{@phlawd_name}#{label}.phlawd" 
           File.open(phlawd_runfile_fullpath, "w"){|f| f.puts phlawd_runfile}
           phlawd_runfile_fullpath 
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
      raise "Not all sequences have the same width" unless @widths.size > 1 and @widths.uniq.size == 1
      File.open(filename, "w") do |f|
        f.puts "#{@seqs.size} #{@widths.first.to_s}"
        @seqs.each{|s| f.puts s} 
      end
    end
  end

end

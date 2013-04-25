module PerpetualPhlawd
  # PHLAWD wrapper
  class PhlawdInstance
    attr_reader :valid, :gene_name
    def initialize(path, phlawd_runner)
      @PHLAWD = phlawd_runner.phlawd
      @log = phlawd_runner.log
      @path = path
      @gene_name = File.basename path # assume the gene name is the folder name 
      @error_msgs = []
      @valid = validate
    end
    def print_error_msgs(prefix)
      @error_msgs.each {|m| $stderr.puts prefix + m}
    end
    def run_initial
      # Ensure runfile exists
      Dir.chdir(@path) do 
        @log.systemlog("#{@PHLAWD} assemble #{runfile}", "PHLAWD STDOUT>>")
        @log.info("Done with instance #{@gene_name}", "<<PHLAWD STDOUT")
      end
    end
    def expected_result_file
      File.join @path, "#{@gene_name}.FINAL.aln.rn"
    end
    private
    def validate
      has_runfile?
    end
    def has_runfile?
      if File.exist? runfile
	res = true
      else
        @error_msgs << "No Runfile found (Missing #{runfile})" 
	res = false
      end
      res
    end
    def runfile
      File.join @path, "#{@gene_name}.phlawd"
    end
  end
  class PhlawdRunner
    attr_reader :phlawd, :log
    def initialize(log, phlawd)
      @phlawd = phlawd
      @log = log
    end
  end
  class Phlawd
    def initialize(opts, log)
      @opts = opts
      @phlawd_runner = PhlawdRunner.new(log, @opts['phlawd_binary'])
      @instances = find_folder_instances
    end
    def print_instances
      @instances.each do |instance|
        $stderr.puts instance.gene_name
        if instance.valid
          $stderr.puts "  OK"
        else
          $stderr.puts "  Validation errors:"
          instance.print_error_msgs("\t")
        end
        $stderr.puts "=="
      end
    end
    def run_initial
      fasta_alignments = []
      # Run phlawd sequentially
      valid_instances.each do |instance| 
        instance.run_initial unless File.exist? instance.expected_result_file 
        if File.exist? instance.expected_result_file
          fasta_alignments << instance.expected_result_file
        else
          $stderr.puts "PHLAWD did not generate #{instance.expected_result_file}"
        end
      end
      fasta_alignments 
    end
    def generate_genbank_autoupdate(dbname, search, cronjob)

      #update command
      params = "#{@phlawd_runner.phlawd} #{search} #{dbname}.tmp #{dbname}"
      cmd = "python #{@opts['phlawd_autoupdater']} #{params}"

      # cronjob that calls the update command
      database_dir = @opts['phlawd_database_dir']
      phlawd_autoupdate_info = @opts['phlawd_autoupdate_info']
      cronjob_path = File.join database_dir, cronjob
      File.open(cronjob_path, "w") do |f| 
        f.puts "# Move to the working dir to rebuild the database"
        f.puts "cd #{database_dir}"
        f.puts "# Log the stdout from the previous attempt"
        f.puts "rm -rf taxdump.tar.*"
        f.puts "date >> #{phlawd_autoupdate_info}.log"
        f.puts "cat #{phlawd_autoupdate_info} >> #{phlawd_autoupdate_info}.log"
        f.puts "# Edit accordingly and (optionally) call from a cronjob"
        f.puts "(#{cmd} 2> update_err ) > #{phlawd_autoupdate_info} &"
      end
    end
    private
    def valid_instances
      @instances.select{|instance| instance.valid}
    end
    def find_folder_instances
      working_dir = @opts['phlawd_working_dir']
      instances = []
      Dir.entries(working_dir).reject{|f| f=~ /^\.+$/}.each do |f|
        path =  File.join working_dir, f
        instances << PhlawdInstance.new(path, @phlawd_runner) 
      end
      instances
    end
  end
  class AutoPhlawd
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
      phlawd_autoupdate_generate 
    end
    private
        def phlawd_autoupdate_generate
          dbdir = File.dirname @db_path
          dbname = File.basename @db_path
          phlawd_autoupdate_file = File.join dbdir, "#{@phlawd_name}_autoupdate.sh"
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
end

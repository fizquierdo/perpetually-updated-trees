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
      @runconfig = {}
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
    def run_update(iteration)
      Dir.chdir(@path) do 
        generate_update_runfile
        cmd = "#{@PHLAWD} assemble #{update_runfile}"
        @log.systemlog("#{cmd} >> PhlawdAssembleUpdateDBinfo.log", "PHLAWD STDOUT>>")
        @log.info("Done with instance #{@gene_name}", "<<PHLAWD STDOUT")
      end
    end
    
    
    def expected_result_file
      File.join @path, "#{@gene_name}.FINAL.aln.rn"
    end
    def method_missing(meth, *args, &block)
      if meth.to_s =~ /^lookup_(.+)$/
        @runconfig[$1] || "Field #{$1} not found"
      else
        super
      end
    end
    def genbank_db_path
      # assume we have an absolute path
      dbpath = self.lookup_db
      if dbpath =~ /^\.\./
        basepath = File.dirname(runfile)  
	dbpath = File.join basepath, dbpath
      end
      File.absolute_path dbpath 
    end
    def generate_update_runfile
      unless File.exist? update_runfile
        FileUtils.cp(runfile, update_runfile)
        File.open(update_runfile, "a") do |f|
          f.puts "updateDB"
        end
      end
    end
    private
    def validate
      has_runfile?
    end
    def has_runfile?
      if File.exist? runfile
	res = true
        # update the config of the instance
        File.open(runfile).each_line do |l|
          field, value = l.chomp.split("=").map{|v| v.strip}
          @runconfig[field] = value
        end
      else
        @error_msgs << "No Runfile found (Missing #{runfile})" 
	res = false
      end
      res
    end
    def runfile
      File.join @path, "#{@gene_name}.phlawd"
    end
    def update_runfile
      File.join @path, "#{@gene_name}updateDB.phlawd"
    end
  end

  class PhlawdRunner
    attr_reader :phlawd, :log
    def initialize(log, phlawd)
      @phlawd = phlawd
      @log = log
    end
    def writelog(msg)
      @log.info msg
    end
  end

  class GenbankDB
    attr_reader :dbname, :clade
    def initialize(instances, opts)
      @instances = instances
      @opts = opts
      @dbname = find_unique_db
      raise "Unable to find unique Genbank DB #{@dbname}" unless File.exist? @dbname
      @clade = ""
    end
    def generate_autoupdate(cronjob)
 
      dbupdate = generate_dbupdate
      return unless File.exist? dbupdate

      #update command
      params = "#{@opts['phlawd_binary']} #{dbupdate} #{@dbname}.tmp #{@dbname}"
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
    def generate_dbupdate
      dbupdate = ""
      update_clades
      if @clade.empty?
        $stderr.puts "  Could not find a common clade for all instances"
      else
        basedir = File.dirname @dbname
        dbupdate = File.join basedir, "db.update"
        File.open(dbupdate, "w") do |f|
	  f.puts "clade = #{@clade}"
	  f.puts "search = #{search_terms}"
	end
      end
      dbupdate
    end
    def search_terms
      @instances.map{|i| i.lookup_search }.join(",")
    end
    def update_clades
      @clade = ""
      clades = []
      @instances.each do |instance|
        clades << instance.lookup_clade
      end
      if clades.uniq.size == 1
        @clade = clades.first
      end
    end
    def find_unique_db
      # assume all instances use the same Genbank DB
      dbnames = []
      @instances.each do |instance|
        dbnames << instance.genbank_db_path
      end
      if dbnames.uniq.size == 1
        # the one and only path for the genbank DB
        dbname = dbnames.first
      else
        # return all of them to report the conflict
        dbname = dbnames.to_s
      end
    end
  end

  class Phlawd
    def initialize(opts, log)
      @opts = opts
      @phlawd_runner = PhlawdRunner.new(log, @opts['phlawd_binary'])
      @instances = find_folder_instances
      @genbank_db = GenbankDB.new(@instances, @opts) 
    end
    def generate_genbank_autoupdate(cronjob)
      @genbank_db.generate_autoupdate(cronjob)
    end

    def print_instances
      @instances.each do |instance|
        $stderr.puts instance.gene_name
        if instance.valid
          $stderr.puts "  Validation OK"
          $stderr.puts "    Clade: #{instance.lookup_clade}"
          $stderr.puts "    Search terms: #{instance.lookup_search}"
        else
          $stderr.puts "  Validation errors:"
          instance.print_error_msgs("\t")
        end
        $stderr.puts "=="
      end
    end
    def add_fasta_alignment(fasta_file)
      if File.exist? fasta_file
        @fasta_alignments << fasta_file
      else
        msg = "PHLAWD did not generate #{fasta_file}"
        $stderr.puts msg
        @phlawd_runner.writelog msg
      end
    end
    def run_initial
      @fasta_alignments = []
      # Run phlawd sequentially
      valid_instances.each do |instance| 
        instance.run_initial unless File.exist? instance.expected_result_file 
        add_fasta_alignment instance.expected_result_file
      end
      @fasta_alignments 
    end
    def run_update(update_key, iteration)
      @fasta_alignments = []
      @phlawd_runner.writelog "Try to run an update for iteration #{iteration}"
      if update_required? update_key
        @phlawd_runner.writelog "Rebuild is required according to PHLAWD autoupdater"
        valid_instances.each do |instance| 
          instance.run_update(iteration)
          add_fasta_alignment instance.expected_result_file
        end
      end
      @fasta_alignments
    end
    def autoupdate_info_file
      @opts['phlawd_autoupdate_info'] || "update_info"
    end
    def autoupdate_info_file_path
      dbdir = File.dirname @genbank_db.dbname
      full_path = File.join dbdir, autoupdate_info_file
      $stderr.puts "#{full_path} not found" unless File.exist? full_path
      full_path
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
        if File.directory? path
          instances << PhlawdInstance.new(path, @phlawd_runner) 
        end
      end
      instances
    end
    def update_required?(update_key)
      update_required = false
      dbdir = File.dirname @genbank_db.dbname
      Dir.chdir dbdir do
        if File.exist?(autoupdate_info_file)
          key = File.open(autoupdate_info_file).readlines.last
          if key =~ /#{update_key}/ 
            update_required = true
          end
        else
          # This should be an error
          @phlawd_runner.writelog "No file #{autoupdate_info_file} from PHLAWD autoupdater in #{dbdir}"
        end
      end
      update_required
    end
  end
end

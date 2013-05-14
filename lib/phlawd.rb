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
end

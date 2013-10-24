require 'logger'
class InstallLogger
  def initialize(name)
    @log ||= Logger.new(name)
    @log.datetime_format = "%Y-%m-%d %H:%M:%S"
  end
  def info(msg)
    @log.info msg
    puts msg
  end
  def error(msg)
    @log.error msg
    $stderr.puts msg
    self.close
    exit
  end
  def exec(cmd, header)
    @log.info "Exec #{header}: #{cmd}"
    stderrfile = "#{header}_tmp_stderr"
    IO.popen("#{cmd} 2> #{stderrfile}") do |io| 
      while(line = io.gets) do 
        @log.info "#{header} std:: " + line 
      end 
      File.open(stderrfile).each_line do |line|
        @log.info "#{header} err:: " + line 
      end
      FileUtils.rm stderrfile
    end
  end
  def close
    @log.close
  end
end

def install_raxml_locally(log)
  # check wget, unzip exists
  %w(wget unzip gcc).each do |tool|
    log.error "#{tool} could not be found. Automated installation aborted." if `which #{tool}`.empty?
  end

  binary_dir = File.expand_path(File.join File.dirname(__FILE__), '..', 'bin')
  FileUtils.mkdir_p binary_dir 

  # RAxML-like programs
  programs = {
    :Parsimonator => {
    :versions => {
    :sse3          => {:binary => "parsimonator-SSE3", :ready => true,:comp => "Makefile.SSE3.gcc"} },
    :link => 'https://github.com/stamatak/Parsimonator-1.0.2/archive/master.zip',
    :folder => 'Parsimonator-1.0.2-master'}, 

    :RaxmlLight => {
    :versions => {
    :sse3          => {:binary => "raxmlLight",         :ready => true,:comp => "Makefile.SSE3.gcc"}, 
    :sse3_pthreads => {:binary => "raxmlLight-PTHREADS",:ready => true,:comp => "Makefile.SSE3.PTHREADS.gcc"}},
    :link => 'https://github.com/stamatak/RAxML-Light-1.0.5/archive/master.zip',
    :folder => 'RAxML-Light-1.0.5-master'},

    :Raxml => {
    :versions => {
    :sse3          => {:binary => "raxmlHPC-SSE3",         :ready => true,:comp => "Makefile.SSE3.gcc"}, 
    :sse3_pthreads => {:binary => "raxmlHPC-PTHREADS-SSE3",:ready => true,:comp => "Makefile.SSE3.PTHREADS.gcc"}},
    :link => 'https://github.com/stamatak/standard-RAxML/archive/master.zip',
    :folder => 'standard-RAxML-master'}
  }
  programs.each do |key, program|
    log.info "\nChecking #{key.to_s}..."
    installed = true
    #zipped = 'master.zip'
    zipped = 'master'
    folder = program[:folder]
    versions = program[:versions]
    versions.each do |key, v|
      if File.exist? File.join binary_dir, v[:binary] 
        log.info "#{key.to_s} available  ... OK"
      else
        v[:ready] = false
        installed = false
        log.info "#{key.to_s} will be installed in #{binary_dir} ..."
      end
    end
    unless installed
      log.error "Failed to download #{binary_name}" unless system "wget --no-check-certificate #{program[:link]}"
      log.error "Failed to unzip #{zipped}" unless system "unzip #{zipped}"
      Dir.chdir(folder) do
        versions.each do |key, v|
          unless v[:ready]
            log.error "Failed to compile #{v[:binary]}" unless system "make -f #{v[:comp]}"
            log.exec "rm *.o", "cleanup"
            log.exec "mv #{v[:binary]} #{binary_dir}", "move"
          end
        end
      end
      log.exec "rm #{zipped}", "cleanup"
      log.exec "rm #{zipped}.zip", "cleanup"
      log.exec "rm -rf #{folder}", "cleanup"
    end
  end
  log.info "All RAxML-family dependencies... OK"
end

# Minimal gems required for remote
def install_gems_remote(log)
  required_gems = %w(net-scp net-ssh)
  required_gems.each do |name| 
    begin 
      gem name
      log.info "Gem #{name} available ... OK"
    rescue #Gem::LoadError
      cmd = "gem install --no-rdoc --no-ri #{name} "
      log.info "Gem #{name} is not installed ... Installing now..."
      log.info "Running: " + cmd
      log.error "Failed to install #{name}" unless system cmd
      log.info "Gem #{name} DONE"
    end
  end
  log.info "All Ruby dependencies... OK\n"
end

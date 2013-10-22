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

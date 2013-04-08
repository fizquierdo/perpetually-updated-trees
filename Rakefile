# tasks
load 'lib/configuration.rb'

opts = PerpetualTreeConfiguration::Configurator.new("config/local_config.yml").conf

def generate_executable(basefile, execfile, bin_dir,  repl)
  text = File.read(basefile)
  repl.each {|elem| text.gsub!(elem[:base], elem[:repl]) }
  File.open(execfile, "w"){ |f| f.puts text}
  system "chmod +x #{execfile}"
  system %{ sudo cp #{execfile} #{bin_dir}/#{execfile} }
  FileUtils.rm execfile
end


desc "Install a ruby executable, copy current templates/configs"
task :install do
  bin_dir = opts['bin_dir'] 
  raise "Path for binaries bin_path not available in config file" if bin_dir.nil? 
  raise "#{bin_dir} not found" unless File.exist? bin_dir
  install_dir = opts['install_dir']
  templatedir = File.join install_dir, "templates"
  scriptdir = File.join install_dir, "scripts"
  libdir = File.join install_dir, "lib"
  datadir = File.join install_dir, "data"
  [install_dir, templatedir, libdir, scriptdir, datadir].each{|dir| system %{sudo mkdir -p #{dir}}}

  repl = [{:base => /LOAD_PATH\.unshift.+$/, :repl => %{LOAD_PATH.unshift "#{install_dir}/lib"}}]
  # main script
  generate_executable("put.rb", "PLANTER", bin_dir, repl)

  # script for finalizing iterations 
  generate_executable("scripts/finish_iteration.rb", "PLANTER_FINISH", bin_dir, repl)

  # the cluster and remote config and the templates related
  system "sudo cp config/cluster/default.config.yml #{install_dir}/templates"
  system "sudo cp config/cluster/remote_config.yml #{install_dir}/templates"
  system "sudo cp config/cluster/*.erb #{install_dir}/templates"
  # the ruby libraries
  system "sudo cp lib/*.rb #{libdir}"
  # the phlawd auto-updater
  system "sudo cp scripts/autoupdate_phlawd_db.py #{scriptdir}"
  # the basic example
  generate_executable("scripts/run_perpetual_example.rb", "run_perpetual_example.rb", scriptdir, repl)
  # the data for the example
  system "sudo cp testdata/* #{datadir}"
  # the iteration summarizer 
  generate_executable("scripts/summarize_results.rb", "summarize_results.rb", scriptdir, repl)
  # script for generation 
  repl = [{:base => /@install_path=.+$/, :repl => %{@install_path="#{install_dir}"}},
          {:base => /^put:.+$/,          :repl => %{put: #{bin_dir}/PLANTER}}]
  generate_executable("scripts/generate_perpetual.rb", "PLANTER_GENERATE", bin_dir, repl)
end

desc "show current configuration"
task :conf do
  opts.each do |k,v|
    puts "#{k}: #{v}"
  end
end


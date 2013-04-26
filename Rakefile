# tasks
load 'lib/configuration.rb'

opts = PerpetualTreeConfiguration::Configurator.new("config/local_config.yml").conf

def syscopy(from, to)
  #system "sudo cp #{from} #{to}"
  system "cp #{from} #{to}"
end
def sysmkdir(dir)
  #system %{sudo mkdir -p #{dir}}
  FileUtils.mkdir_p dir
end

def replace_in_file(basefile, newfile, repl)
  text = File.read(basefile)
  repl.each {|elem| text.gsub!(elem[:base], elem[:repl]) }
  File.open(newfile, "w"){ |f| f.puts text}
end

def generate_executable(basefile, execfile, bin_dir,  repl)
  puts "Generating #{execfile}"
  replace_in_file basefile, execfile, repl
  system "chmod +x #{execfile}"
  syscopy execfile, File.join(bin_dir,execfile)
  FileUtils.rm execfile
end



desc "Install a ruby executable, copy current templates/configs"
task :install do
  install_dir = File.expand_path opts['install_dir']
  bin_dir     = File.expand_path opts['bin_dir'] 
  templatedir = File.join install_dir, "templates"
  scriptdir   = File.join install_dir, "scripts"
  libdir      = File.join install_dir, "lib"
  datadir     = File.join install_dir, "data" # TODO not sure you need this
  [bin_dir, install_dir, templatedir, libdir, scriptdir, datadir].each{|dir| sysmkdir dir}
  raise "Path for binaries bin_path not available in config file" if bin_dir.nil? 
  raise "#{bin_dir} not found" unless File.exist? bin_dir

  repl = [{:base => /LOAD_PATH\.unshift.+$/, :repl => %{LOAD_PATH.unshift "#{install_dir}/lib"}}]
  # main script
  generate_executable("put.rb", "PLANTER", bin_dir, repl)

  # script for finalizing iterations 
  generate_executable("scripts/finish_iteration.rb", "PLANTER_FINISH", bin_dir, repl)

  # the cluster and remote config and the templates related
  %w(default.config.yml remote_config.yml *.erb).each{ |f| syscopy "config/cluster/#{f}", templatedir}
  repl_elems =  [{:base => "PLANTER_FINISH",  :repl => "#{bin_dir}/PLANTER_FINISH"}]
  repl_file  =  "#{templatedir}/template_raxmllight.slurm.erb"
  replace_in_file repl_file, repl_file, repl_elems
  # the ruby libraries
  syscopy "lib/*.rb", libdir
  # the phlawd auto-updater
  syscopy "scripts/autoupdate_phlawd_db.py", scriptdir
  # the basic example
  generate_executable("scripts/run_perpetual_example.rb", "run_perpetual_example.rb", scriptdir, repl)
  # the data for the example
  #puts "Copying testdata"
  #syscopy "testdata/*", datadir
  FileUtils.cp_r "testdata", install_dir
  #puts "Copying done"
  # the iteration summarizer 
  generate_executable("scripts/summarize_results.rb", "summarize_results.rb", scriptdir, repl)
  # script for generation 
  repl = [{:base => /@install_path=.+$/, :repl => %{@install_path="#{install_dir}"}},
          {:base => /^put:.+$/,          :repl => %{put: #{bin_dir}/PLANTER}},
          {:base => "PLANTER_PATH",      :repl => "#{bin_dir}/PLANTER"}]
  generate_executable("scripts/generate_perpetual.rb", "PLANTER_GENERATE", bin_dir, repl)
end

desc "show current configuration"
task :conf do
  opts.each do |k,v|
    puts "#{k}: #{v}"
  end
end

desc "tutorial"
task :tutorial, :parsi, :best do |t, args|
  wdir = "tutorial2"
  args.with_defaults(:parsi => 3, :best => 1)
  FileUtils.mkdir wdir
  Dir.chdir(wdir) do 
    system "../testinstall/bin/PLANTER_GENERATE loni #{args[:best]} #{args[:parsi]} ../testdata/lonicera_10taxa.rbcL.phy"
  end
end


# tasks
load 'lib/configuration.rb'

opts = PerpetualTreeConfiguration::Configurator.new("config/local_config.yml").conf

pumper_libs = %w(configuration perpetual_evaluation phlawd rphylip experiment pumper_helpers
                  trollop pumper_helpers floatstats perpetual_utils rnewick)

def syscopy(from, to)
  #system "sudo cp #{from} #{to}"
  system "cp #{from} #{to}"
end
def syslink(from, to)
  system "ln --force #{from} #{to}"
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

def generate_tutorial(pumper_bin_dir, wdir, args_best, args_parsi)
  # from the testdata
  init_phy = "../testdata/lonicera_10taxa.rbcL.phy"
  update_args = "--name loni_part --update-phy ../testdata/lonicera_23taxa.rbcL.phy --parsi-size 2 --bunch-size 1 --config-file pumper_config_loni.yml"
  FileUtils.mkdir wdir
  Dir.chdir(wdir) do 
    # Generate the initial iteration script with the PUmPER generator
    system "#{pumper_bin_dir}/PUMPER_GENERATE loni #{args_best} #{args_parsi} #{init_phy}"
    # Generate the update iteration script directly calling PUmPER 
    update_cmd = "#{pumper_bin_dir}/PUMPER #{update_args}"
    system "echo #{update_cmd} > update_loni_partitions.sh"
  end
end

def generate_pipeline(pumper_bin_dir, wdir)
  # Assume pln.db is available (can be downloaded from phlawd.net)
  FileUtils.mkdir wdir
  Dir.chdir(wdir) do 
    system "#{pumper_bin_dir}/PUMPER_GENERATE pipeline"
    system "ln ../pln.db alignments/GenBank/pln.db"
  end
end


# TASKS
desc "Install the standalone version" 
task :install_standalone do
  # Configuration
  install_dir = File.expand_path opts['standalone_install_dir']
  bin_dir     = File.expand_path opts['standalone_bin_dir'] 
  scriptdir   = File.join install_dir, "scripts"
  libdir      = File.join install_dir, "lib"
  [bin_dir, install_dir, libdir, scriptdir].each{|dir| sysmkdir dir}
  raise "Path for binaries bin_path not available in config file" if bin_dir.nil? 
  raise "#{bin_dir} not found" unless File.exist? bin_dir

  repl = [{:base => /LOAD_PATH\.unshift.+$/, :repl => %{LOAD_PATH.unshift "#{install_dir}/lib"}}]
  # main script
  generate_executable("put.rb", "PUMPER", bin_dir, repl)

  # the ruby libraries
  pumper_libs += %w(starter rraxml)
  pumper_libs.each do |filename|
    syscopy "lib/#{filename}.rb", libdir  
  end
  # the raxml binaries
  syslink "bin/*", bin_dir
  # the basic example
  generate_executable("scripts/run_perpetual_example.rb", "run_perpetual_example.rb", scriptdir, repl)
  FileUtils.cp_r "testdata", install_dir
  # the iteration summarizer 
  generate_executable("scripts/summarize_results.rb", "summarize_results.rb", scriptdir, repl)
  # script for generation 
  repl = [{:base => /@install_path=.+$/, :repl => %{@install_path="#{install_dir}"}},
          {:base => /^put:.+$/,          :repl => %{put: #{bin_dir}/PUMPER}},
          {:base => "PUMPER_VERSION",    :repl => 'standalone'},
          {:base => "PUMPER_PATH",      :repl => "#{bin_dir}/PUMPER"}]
  generate_executable("scripts/generate_perpetual.rb", "PUMPER_GENERATE", bin_dir, repl)
end

desc "Install the remote version" 
task :install_remote do
  # Configuration
  install_dir = File.expand_path opts['remote_install_dir']
  bin_dir     = File.expand_path opts['remote_bin_dir'] 
  scriptdir   = File.join install_dir, "scripts"
  libdir      = File.join install_dir, "lib"
  templatedir = File.join install_dir, "templates"
  [bin_dir, install_dir, templatedir, libdir, scriptdir].each{|dir| sysmkdir dir}
  raise "Path for binaries bin_path not available in config file" if bin_dir.nil? 
  raise "#{bin_dir} not found" unless File.exist? bin_dir

  repl = [{:base => /LOAD_PATH\.unshift.+$/, :repl => %{LOAD_PATH.unshift "#{install_dir}/lib"}},
          {:base => /version = \'standalone\'/, :repl => %{version = \'remote\'}}]
  # main script
  generate_executable("put.rb", "PUMPER", bin_dir, repl)
  # script for finalizing iterations 
  generate_executable("scripts/finish_iteration.rb", "PUMPER_FINISH", bin_dir, repl)

  # the ruby libraries
  pumper_libs += %w(starter_remote perpetual_updater remote_job)
  pumper_libs.each do |filename|
    syscopy "lib/#{filename}.rb", libdir  
  end

  # the cluster and remote config and the templates related
  %w(default.config.yml remote_config.yml *.erb).each{ |f| syscopy "config/cluster/#{f}", templatedir}
  repl_elems =  [{:base => "PUMPER_FINISH",  :repl => "#{bin_dir}/PUMPER_FINISH"}]
  repl_file  =  "#{templatedir}/template_raxmllight.slurm.erb"
  replace_in_file repl_file, repl_file, repl_elems
  # the phlawd auto-updater
  syscopy "scripts/autoupdate_phlawd_db.py", scriptdir

  # the basic example (TODO check if makes sense for remote, do another one?)
  generate_executable("scripts/run_perpetual_example.rb", "run_perpetual_example.rb", scriptdir, repl)
  FileUtils.cp_r "testdata", install_dir
  # the iteration summarizer 
  generate_executable("scripts/summarize_results.rb", "summarize_results.rb", scriptdir, repl)
  # script for generation 
  repl = [{:base => /@install_path=.+$/, :repl => %{@install_path="#{install_dir}"}},
          {:base => /^put:.+$/,          :repl => %{put: #{bin_dir}/PUMPER}},
          {:base => "PUMPER_VERSION",    :repl => 'remote'},
          {:base => "PUMPER_PATH",       :repl => "#{bin_dir}/PUMPER"}]
  generate_executable("scripts/generate_perpetual.rb", "PUMPER_GENERATE", bin_dir, repl)
end

desc "show current configuration"
task :conf do
  opts.each do |k,v|
    puts "#{k}: #{v}"
  end
end

pumper_standalone_bin_dir = File.expand_path opts['standalone_bin_dir'] 
pumper_remote_bin_dir     = File.expand_path opts['remote_bin_dir'] 
timestr = Time.now.to_i.to_s

# Tutorial examples (using PUmPER without PHLAWD)
desc "Run generator for the getting-started tutorial (standalone)"
task :tutorial_standalone, :parsi, :best do |t, args|
  wdir = "ztutorial_standalone_from_rake_" + timestr
  args.with_defaults(:parsi => 3, :best => 1)
  generate_tutorial pumper_standalone_bin_dir, wdir, args[:best], args[:parsi]
end
desc "Run generator for the getting-started tutorial (remote)"
task :tutorial_remote, :parsi, :best do |t, args|
  wdir = "ztutorial_remote_from_rake_" + timestr
  args.with_defaults(:parsi => 3, :best => 1)
  generate_tutorial pumper_remote_bin_dir, wdir, args[:best], args[:parsi]
end

# Adapt to test PHLAWD + remote installation
desc "Create remote demo pipeline and link small pln.db"
task :pipeline_remote do
  wdir = "znewpipeline_remote_from_rake_" + timestr
  generate_pipeline pumper_remote_bin_dir, wdir
end
desc "Create standalone demo pipeline and link small pln.db"
task :pipeline_standalone do
  wdir = "znewpipeline_remote_from_rake_" + timestr
  generate_pipeline pumper_standalone_bin_dir, wdir
end

# install and run tutorial
desc "Remove tutorial"
task :tutorial_clean do
  system "rm -rf ztutorial_*_from_rake*"
end
desc "Install standalone and generate tutorial"
task :demo => [:install_standalone, :tutorial_clean, :tutorial_standalone] do
  puts "ls ztutorial_*_from_rake*"
end


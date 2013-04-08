#!/usr/bin/env ruby
$LOAD_PATH.unshift "/opt/perpetualtree/lib"
require 'logger'
require 'fileutils'
require 'configuration'
require 'example'


# Config
raise "Usage #{$0} standalone.yml" unless ARGV.size == 1
config_file = ARGV.first
opts = PerpetualTreeConfiguration::Configurator.new(config_file).conf
remote = opts['remote'] || false

# Log everything here
log_filename = opts['example_log_file_name'] || "perpetual.log"
log = PerpetualTreeExample::ExampleLogger.new File.expand_path(log_filename)

# Relevant data for PHLAWD 
FileUtils.mkdir_p opts['phlawd_working_dir'] 
phlawd = PerpetualTreeExample::Phlawd.new(opts, log)
# Check it PHLAWD has a database to work with
db_dir = File.dirname opts['phlawd_database']
if File.exist? db_dir
  raise "Database #{opts['phlawd_database']} not found" unless File.exist?(opts['phlawd_database'])
else
  FileUtils.mkdir_p db_dir
  Dir.chdir db_dir do
    phlawd.setupdb 
  end
end
fasta_alignment = File.join opts['phlawd_working_dir'], opts['first_fasta_alignment']

log.info "### ITERATION 1 [INITIAL] ###"
# Run iteration 1 of PHLAWD (generate fasta_alignment)
phlawd.run_initial unless File.exist?(fasta_alignment)

log.info "Translating fasta into phylip"
phylip_alignment = fasta_alignment.to_s + ".phy"
PerpetualTreeExample::Fasta.new(fasta_alignment).to_phylip(phylip_alignment)
log.info "Phylip file: #{phylip_alignment}"

# Run iteration 1 of Raxml searches
log.info "First search iteration, Using #{opts['put']}"
log.info "Run experiment...."
cmd = "#{opts['put']} --name #{opts['run_name']} --initial-phy #{phylip_alignment} --parsi-size #{opts['parsimony_starting_size']} --bunch-size #{opts['best_bunch_size']} --standalone-config-file #{config_file}"
cmd += " --remote-config-file #{opts['remote_config_file']} --remote" if remote
log.systemlog cmd
log.info("First iteration launched")

# Now the updates should be automatic

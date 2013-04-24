#!/usr/bin/env ruby
$LOAD_PATH.unshift "/opt/perpetualtree/lib"
require 'logger'
require 'fileutils'
require 'configuration'
require 'perpetual_utils' 
require 'phlawd'


# Config
raise "Usage #{$0} standalone.yml" unless ARGV.size == 1
config_file = ARGV.first
opts = PerpetualTreeConfiguration::Configurator.new(config_file).conf
remote = opts['remote'] || false

# Log everything here
log_filename = opts['example_log_file_name'] || "perpetual.log"
log = PerpetualTreeUtils::MultiLogger.new File.expand_path(log_filename)

# Relevant data for PHLAWD (first assume 1 instance)
gene = "rbcL"
wdir =  File.join opts['phlawd_working_dir']
phlawd = PerpetualPhlawd::Phlawd.new(opts['phlawd_binary'], wdir, log)
phlawd.print_instances

log.info "### ITERATION 1 [INITIAL] ###"
# Run iteration 1 of PHLAWD (generate fasta_alignment)
phlawd.run_initial 

exit

log.info "Translating fasta into phylip"
fasta_alignment = File.join wdir, "rbcL.FINAL.aln.rn"
phylip_alignment = fasta_alignment.to_s + ".phy"
PerpetualTreeUtils::Fasta.new(fasta_alignment).to_phylip(phylip_alignment)
log.info "Phylip file: #{phylip_alignment}"

# Run iteration 1 of Raxml searches
log.info "First search iteration, Using #{opts['put']}"
log.info "Run experiment...."
cmd = "#{opts['put']} --name #{opts['run_name']} --initial-phy #{phylip_alignment} --parsi-size #{opts['parsimony_starting_size']} --bunch-size #{opts['best_bunch_size']} --standalone-config-file #{config_file}"
cmd += " --remote-config-file #{opts['remote_config_file']} --remote" if remote
log.systemlog cmd
log.info("First iteration launched")

# Now the updates should be automatic

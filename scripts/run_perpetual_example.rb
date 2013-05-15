#!/usr/bin/env ruby
$LOAD_PATH.unshift "/opt/perpetualtree/lib"
require 'logger'
require 'fileutils'
require 'configuration'
require 'perpetual_utils' 
require 'phlawd'
require 'rphylip'


# Config
raise "Usage #{$0} standalone.yml" unless ARGV.size == 1
config_file = ARGV.first
opts = PerpetualTreeConfiguration::Configurator.new(config_file).conf
remote = opts['remote'] || false

# Log everything here
log_filename = opts['example_log_file_name'] || "perpetual.log"
log = PerpetualTreeUtils::MultiLogger.new File.expand_path(log_filename)

# Relevant data for PHLAWD (first assume 1 instance)
phlawd = PerpetualPhlawd::Phlawd.new(opts, log)
phlawd.print_instances

log.info "### PHLAWD ITERATION 1 [INITIAL] ###"
# Run iteration 1 of PHLAWD (generate fasta_alignment)
fasta_alignments = phlawd.run_initial 

updater = "#{opts['run_name']}_cron_phlawd_extender.sh"
log.info "Generating updater of GenBank DB: #{updater}"
phlawd.generate_genbank_autoupdate(updater)

if fasta_alignments.empty?
  puts "Nothing to work with"
  exit
else
  p fasta_alignments
end

# concatenate into one single phylip
phlawd_fastas = PerpetualTreeUtils::FastaAlignmentCollection.new fasta_alignments, log
phlawd_fastas.build_supermatrix(opts, 0)
aln = phlawd_fastas.aln
part = phlawd_fastas.part

raise "Alignment not available" unless aln and File.exist? aln


# Run iteration 1 of Raxml searches
log.info "### SEARCH ITERATION 1 [INITIAL] ###"
log.info "Using #{opts['put']}"
cmd = "#{opts['put']} --name #{opts['run_name']} --initial-phy #{aln} --partitions #{part} --parsi-size #{opts['parsimony_starting_size']} --bunch-size #{opts['best_bunch_size']} --standalone-config-file #{config_file}"
cmd += " --remote" if remote
log.systemlog cmd
log.info("First iteration launched")

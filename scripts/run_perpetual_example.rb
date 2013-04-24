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
wdir =  File.join opts['phlawd_working_dir']
phlawd = PerpetualPhlawd::Phlawd.new(opts['phlawd_binary'], wdir, log)
phlawd.print_instances

log.info "### PHLAWD ITERATION 1 [INITIAL] ###"
# Run iteration 1 of PHLAWD (generate fasta_alignment)
fasta_alignments = phlawd.run_initial 

if fasta_alignments.empty?
  puts "Nothing to work with"
  exit
else
  p fasta_alignments
end

# create the phylip alignments
phylip_alignments = fasta_alignments.map do |fasta| 
  log.info "Translating #{fasta} into phylip"
  phylip_name = fasta.to_s + ".phy"
  PerpetualTreeUtils::Fasta.new(fasta).to_phylip(phylip_name)
  phylip_name
end

# concatenate into one single phylip
raise "No phylip alignment available" if phylip_alignments.empty?
msa_name = "phlawd_aln_t#{Time.now.to_i}"
first_phylip = MultiPartition::Phylip.new phylip_alignments.shift
log.info "Building alignment called #{msa_name}"
msa = MultiPartition::SpeciesPhylip.new(first_phylip, msa_name)
phylip_alignments.each do |phylip_filename|
  log.info "Adding #{phylip_filename}"
  msa.concat_phylip(MultiPartition::Phylip.new phylip_filename)
end
msa.save

# Run iteration 1 of Raxml searches
log.info "### SEARCH ITERATION 1 [INITIAL] ###"
log.info "Using #{opts['put']}"
cmd = "#{opts['put']} --name #{opts['run_name']} --initial-phy #{msa_name}.phy --partitions #{msa_name}.model --parsi-size #{opts['parsimony_starting_size']} --bunch-size #{opts['best_bunch_size']} --standalone-config-file #{config_file}"
cmd += " --remote" if remote
log.systemlog cmd
log.info("First iteration launched")

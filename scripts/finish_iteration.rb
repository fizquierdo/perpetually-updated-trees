#!/usr/bin/env ruby
$LOAD_PATH.unshift "/opt/perpetualtree/lib"
require 'perpetual_evaluation'

# This is a script to finalize and iplant iteration (remotely computed in stampede)
 
begin
  # Assume the script is called externally with the correct arguments
  iteration = PerpetualTreeEvaluation::IterationFinisher.new ARGV

  # The rest of the code to finish the iteration
  r = PerpetualTreeEvaluation::ProjectResults.new :info_files_dir => iteration.results_dir, 
                                                  :best_set => ARGV[1],
                                                  :expected_set => iteration.tree_search_bunch_size

  # Find out if all expected trees are available
  if r.has_collected_all_trees?
    # If iteration really finished, add the trees to the final file
    iteration.add_best_trees(r.lh_rank)
    # Now the first tree in the bunch is the best and we upload it
    iteration.upload_best_tree
    # Get the best tree name (this step coul be optionsal)
    best_tree_name= ""
    r.lh_rank.each_with_index do |t, i|
     iteration.log.puts  "Tree rank #{i+1}: LH #{t[:lh]}, name: #{t[:topology_name]}" 
     best_tree_name = t[:topology_name] if i == 0
    end
    # And now we could do further post-analysis (consensus / RF distance etc )
    # Send a notification
    titlestr = "Iteration #{iteration.update_id} DONE for project #{iteration.name}"
    iteration.add_finish_label
  else
    titlestr = "Missing trees for Iteration #{iteration.update_id} for project #{iteration.name}"
    iteration.log.puts  "#{r.lh_rank.size} available trees, expected #{iteration.tree_search_bunch_size}" 
  end
  iteration.log.close
  mailer = PerpetualTreeEvaluation::Mailer.new(:mail_to => iteration.mail_to, 
                                               :title => titlestr, 
                                               :content_file => iteration.iteration_log_filename)
  mailer.send_mail

rescue Exception => e
  iteration.log.puts "ERROR Exception: #{e}"
  raise e
end
  





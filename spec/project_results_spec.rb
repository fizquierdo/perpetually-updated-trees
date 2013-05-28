
# Describe connection with the remote machine
require_relative '../lib/perpetual_evaluation'

describe "completed project" do
  before(:each) do 
    @info_files_dir = File.expand_path("spec/project_results_data/ml_trees")
    @best_set = 2
    @expected_set = 3
    @p =  PerpetualTreeEvaluation::ProjectResults.new :info_files_dir => @info_files_dir,
                                                      :best_set => @best_set,
                                                      :expected_set => @expected_set 
  end
  it "should respond to best set" do
    expect(@p.best_set).to eq @best_set
  end
  it "should respond to expected set" do
    expect(@p.expected_set).to eq @expected_set
    @p.expected_set = 1
    expect(@p.expected_set).to eq 1
  end
  it "should return an ordered rank of log likelihoods" do
    lhs = @p.lhs
    expect(lhs.size).to eq @expected_set
    expect(lhs.first).to be > lhs.last
    expect(lhs.last).to  be < lhs.first
  end
  it "should return the best like likelihoods" do
    best_lhs = @p.best_lhs
    expect(best_lhs.size).to eq @best_set
    expect(best_lhs[0]).to eq -3474.374716
    expect(best_lhs[1]).to eq -3474.437354
  end
  it "should have gathered all trees" do
    expect(@p.has_collected_all_trees?).to be_true
  end
end


# Describe connection with the remote machine
require_relative '../lib/perpetual_evaluation'

describe PerpetualTreeEvaluation::ProjectResults do
  before(:all) do
    @info_files_dir = File.expand_path("spec/project_results_data/ml_trees")
    @best_set = 2
    @expected_set = 3
  end
  describe "completed project" do
    before(:each) do 
      @p =  PerpetualTreeEvaluation::ProjectResults.new :info_files_dir => @info_files_dir,
                                                        :best_set => @best_set,
                                                        :expected_set => @expected_set 
    end
    it "respond to best set" do
      expect(@p.best_set).to eq @best_set
    end
    it "respond to expected set" do
      expect(@p.expected_set).to eq @expected_set
      @p.expected_set = 1
      expect(@p.expected_set).to eq 1
    end
    it "return an ordered rank of log likelihoods" do
      p @p.lh_rank
      lhs = @p.lhs
      expect(lhs.size).to eq @expected_set
      expect(lhs.first).to be > lhs.last
      expect(lhs.last).to  be < lhs.first
    end
    it "return the best like likelihoods" do
      best_lhs = @p.best_lhs
      expect(best_lhs.size).to eq @best_set
      expect(best_lhs[0]).to eq -3474.374716
      expect(best_lhs[1]).to eq -3474.437354
    end
    it "has gathered all trees" do
      expect(@p.has_collected_all_trees?).to be_true
    end
  end
  describe "incompleted project" do
    before(:all) do 
      @incomplete_dir = "incomplete_tmp"
      FileUtils.mkdir @incomplete_dir
      Dir.entries(@info_files_dir).select{|f| f =~ /^RAxML_info/}.each do |f|
        file_path = File.join @info_files_dir, f
        FileUtils.cp file_path, @incomplete_dir
      end
    end
    before(:each) do 
      @pending =  PerpetualTreeEvaluation::ProjectResults.new :info_files_dir => @incomplete_dir,
                                                              :best_set => @best_set,
                                                              :expected_set => @expected_set 
    end
    it "has not gathered all trees" do
      expect(@pending.has_collected_all_trees?).to be_false
    end
    after(:all) do 
      FileUtils.rm_rf @incomplete_dir
    end
  end
end

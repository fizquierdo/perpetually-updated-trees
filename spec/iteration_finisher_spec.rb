
# Describe connection with the remote machine
require_relative '../lib/perpetual_evaluation'

describe PerpetualTreeEvaluation::IterationFinisher do
  def generate_tmp_dir
    @tmp_iter_dir = File.expand_path "tmp_iter_dir"
    @data = "project_results_data"
    FileUtils.mkdir @tmp_iter_dir
    datadir = File.join(File.expand_path(File.dirname(__FILE__)), @data)
    FileUtils.cp_r datadir, @tmp_iter_dir
  end
  before(:each) do
    generate_tmp_dir
    @default_args = {
      bestML_bunch: File.join(@tmp_iter_dir, "#{@data}/best_ml_trees/best_bunch.nw"),
      num_bestML_trees: 2,
      mail_to: "fer.izquierdo@gmail.com",
      update_id: 0,
      results_dir: File.join(@tmp_iter_dir, "#{@data}/ml_trees"),
      iteration_results_filename: "iteration_results.txt",
      name: "pipeline_1368806488",
      tree_search_bunch_size: 3
    }
  end
  context "is correctly initialized" do
    subject {PerpetualTreeEvaluation::IterationFinisher.new @default_args.values}
    its(:update_id)             {should eq 0}
    its(:name)			{should eq "pipeline_1368806488"}
    its(:tree_search_bunch_size){should eq 3}
    its(:mail_to)		{should eq "fer.izquierdo@gmail.com"}
  end
  # TODO this is not working 
=begin
  describe " with a log " do
    it " should have detailed content" do 
      @iteration  = PerpetualTreeEvaluation::IterationFinisher.new @default_args.values
      @logfile = @iteration.iteration_log_filename
      p @iteration.iteration_log_filename
      content_lines = File.open(@logfile).readlines
      expect(content_lines.first).to match "These are the results for iteration #{@iteration.update_id}"
    end 
  end
=end
=begin
  describe "addition of trees" do
    let(:lh_rank) do 
      [{:lh=>-3474.374716, :runtime=>0.09045, :topology_name=>"pipeline_1368806488_000_002", :support_topology=>"RAxML_fastTreeSH_Support.SCORING_pipeline_1368806488_000_002"}, 
       {:lh=>-3474.437354, :runtime=>0.238125, :topology_name=>"pipeline_1368806488_000_000", :support_topology=>"RAxML_fastTreeSH_Support.SCORING_pipeline_1368806488_000_000"}, 
       {:lh=>-3474.437354, :runtime=>0.105881, :topology_name=>"pipeline_1368806488_000_001", :support_topology=>"RAxML_fastTreeSH_Support.SCORING_pipeline_1368806488_000_001"}]
    end
    before(:each) do
      @iter = PerpetualTreeEvaluation::IterationFinisher.new @default_args.values
      #@iter.add_best_trees(lh_rank)
      p File.open(@iter.iteration_log_filename).readlines
    end
    it "log records best trees" do
      content_lines = File.open(@iter.iteration_log_filename).readlines
      expect(content_lines.last).to match /^Tree rank 2: LH -3474.437354 Selected tree is pipeline_1368806488_000_000/
    end
  end
=end
  after(:each) do
    FileUtils.rm_rf @tmp_iter_dir 
  end
end

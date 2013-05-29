
# Describe connection with the remote machine
require 'socket'
require 'net/ssh'
require 'net/scp'
require_relative '../lib/configuration'

# User should edit this file after install
config_file = "testinstall/perpetualinstall/templates/remote_config.yml"

describe "remote connection" do
  before(:all) do
    @conf = PerpetualTreeConfiguration::Configurator.new(config_file).conf
  end
  describe "has correct configuration in place" do
    it "should be established from local machine" do
      machine = Socket.gethostname
      machine.should == @conf['local_machine']
    end
    it "should have a remote machine" do
      @conf['remote_machine'].should_not be_nil
    end
    it "should have a remote path" do
      @conf['remote_path'].should_not be_nil
    end
    it "should have a remote user" do
      @conf['remote_user'].should_not be_nil
    end
    it "should have a local machine" do
      @conf['local_machine'].should_not be_nil
    end
    it "should have a local user" do
      @conf['local_user'].should_not be_nil
    end
    it "should have a local port" do
      @conf['local_port'].should_not be_nil
      @conf['local_port'].should match /^[0-9]+/
    end
  end


  describe "can be established" do
    def connect(user)
       Net::SSH.start(@conf['remote_machine'], user)
    end
    it "should connect" do
      expect{connect @conf['remote_user']}.not_to raise_error(Net::SSH::AuthenticationFailed)
    end
    it "should not connect" do
      expect{connect "nouser"}.to raise_error(Net::SSH::AuthenticationFailed)
    end
  end
  describe "can execute remote operations" do
    def connect_ssh
       Net::SSH.start(@conf['remote_machine'], @conf['remote_user']){|ssh| yield(ssh)}
    end
    before(:all) do 
      @testdir = File.join @conf['remote_path'], "testdir"
      connect_ssh{|ssh| res = ssh.exec!("mkdir #{@testdir}")}
    end
    it "should create a test dir" do
      connect_ssh do |ssh|
        dirname = ssh.exec!("ls #{@testdir}")
	dirname.should be_nil
        wrong_dirname = ssh.exec!("ls unexisting_file")
	wrong_dirname.should == "ls: cannot access unexisting_file: No such file or directory\n" 
      end
    end
    describe "can transfer data" do
      before(:all) do 
        Net::SCP.start(@conf['remote_machine'], @conf['remote_user']) do |scp|
          Dir.chdir("spec/project_results_data/ml_trees") do
            Dir.entries(Dir.pwd).select{|f| f=~ /^RAxML/}.each do |f|
	      #puts "Uploading #{f}"
              scp.upload!(f, @testdir)
            end
          end
        end
      end
      it "should copy data from local to remote" do
        connect_ssh do |ssh|
          dir_entries = ssh.exec!("ls #{@testdir}")
          dir_entries.should_not be_nil
          dir_entries.split("\n").size.should == 21
        end
      end
      describe "can transfer data back" do
        def remote_copy(files)
          connect_ssh do |ssh|
            path = "#{@conf['local_user']}@#{@conf['local_machine']}:#{Dir.pwd}/#{@local_testdir}" 
            res = ssh.exec!("cd #{@testdir} && scp -P #{@conf['local_port']} #{files} #{path}")
          end
        end
        before(:each) do
	  @local_testdir = "testdir"
	  FileUtils.mkdir @local_testdir
	end
        it "should copy all data from remote to local" do
	  remote_copy "*"
          raxml_files = Dir.entries(@local_testdir).select{|f| f=~ /^RAxML/}
	  raxml_files.size.should == 21
        end
	filenames = {RAxML_info: 6, RAxML_result: 6, RAxML_log: 3, RAxML_fastTree: 6}
	filenames.keys.each do |key|
          it "should copy all #{key} files (#{filenames[key]})" do
	    remote_copy "#{key}*"
            raxml_files = Dir.entries(@local_testdir).select{|f| f=~ /^#{key}/}
	    raxml_files.size.should == filenames[key]
          end
	end
        after(:each) do
	  FileUtils.rm_rf @local_testdir 
	end
      end
    end
    after(:all) do
      connect_ssh{ |ssh| res = ssh.exec!("rm -rf #{@testdir}")}
    end
  end

end


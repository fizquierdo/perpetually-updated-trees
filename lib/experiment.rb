#!/usr/bin/env ruby
#require 'rphylip'
require 'fileutils'
require 'yaml'

module ExperimentTable

class Experiment
  def initialize(name, basedir)
    @name = name
    @base_dir = basedir
  end
  def dirname(a)
    File.join @base_dir, 'experiments', @name, a
  end
  def last_bunch_dir
    dirs = Dir.entries(dirname("output")).select{|f| f =~ /^bunch/}
    dirs.sort_by{|s| s.split("_").last.to_i}.last
  end
  def setup_dirs
    setup_ready = true
    %w(alignment output).map{|n| self.dirname n}.each do |dir|
      if File.exist?(dir)
        puts "Exists #{dir}"
        setup_ready = false # to avoid overwrite
      else
        FileUtils.mkdir_p dir
      end
    end
    setup_ready
  end
end

class ExperimentList
  # Persistent storage in .yml file of the experiment status
  attr_accessor :name, :date
  def initialize(expfile)
    @expfile = expfile
    File.open(expfile, "w"){|f| f.puts "---"} unless File.exist?(expfile)
    @list = YAML.load_file(expfile) || Array.new
  end
  def add(opts)
    name_available = self.name_available?(opts[:name]) 
    if name_available
      newexp = {:name => opts[:name], :date => Time.now}
      #newexp.merge!({:fake_phy => opts[:fake_phy]}) unless opts[:fake_phy].nil?
      [:fake_phy, :initial_phy, :parsi_size, :bunch_size].each do |label|
        newexp.merge!({label => opts[label]}) unless opts[label].nil?
      end
      @list.push newexp
      self.save
      true
    end
  end
  def value(name, label)
    e = self.find_by_name(name) 
    e[label] || "?"
  end
  def update(name, step, state)
    e = self.find_by_name(name) 
    unless e.nil?
      @list.each do |item|
        if item[:name] == name
          if item[step].nil?
            item[step] = state
          else
            item[step] += " " + state
          end
        end
      end
    end
    self.save
  end
=begin
  def last_iteration(name)
    e = self.find_by_name(name) 
    e.last_bunch_dir unless e.nil?
  end
=end
  def show
    puts "Current Experiments"
    puts "ID\tname"
    @list.each_with_index  do |item, i|
      fake_name = item[:fake_phy].nil? ? "-" : File.basename(item[:fake_phy]) 
      initial_name = item[:initial_phy].nil? ? "-" : File.basename(item[:initial_phy]) 
      parsi_size = item[:parsi_size] || "?"
      bunch_size = item[:bunch_size] || "?"
      str = "#{i}\t#{item[:name]}"
      str += " \tinit: #{initial_name}" unless initial_name.empty?
      str += " \tfake: #{fake_name}" unless fake_name.empty?
      str += " Best LH: #{item["bestLH"]} (parsi #{parsi_size}, bunch end size #{bunch_size})"
      puts str
      item.keys.select{|k| k =~ /^u\d+$/}.sort.each do |update_key|
        puts "  #{update_key}: #{item[update_key]}"
      end
    end
  end
  def remove(name)
    item = find_by_name(name)
    unless item.nil?
      @list.delete(item) 
      self.save
    end
  end
  def save
    File.open(@expfile, "w"){|f| f.write @list.to_yaml}
    #puts "Experiment list updated"
  end
  def name_available?(name)
    existing_items = find_by_name(name)
    unless existing_items.nil?
       if existing_items.size >= 1
         puts "A experiment with this name exists already"
         p existing_items
         return false
       end
    end
    return true
  end
  protected
  def find_by_name(name)
    @list.find{|e| e[:name] == name}
  end
end
end

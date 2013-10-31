require 'pathname'
class String
  # colorization
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end
  def red
    colorize(31)
  end
  def green
    colorize(32)
  end
  def yellow
    colorize(33)
  end
  def pink
    colorize(35)
  end
end

def pumper_path(path)
  shortpath = Pathname.new(path).relative_path_from Pathname.new(Dir.pwd)
  shortpath.to_s
end

def pumper_time
  t = Time.now
  t.strftime("%Y-%m-%d %H:%M:%S")
end

def pumper_random_seed
  maxnum = 10000
  seed = 1234
  if defined? Random
    seed = Random.rand maxnum
  elsif defined? rand
    seed = rand maxnum
  elsif defined? shuffle
    seed = (1..maxnum).times.shuffle.first
  else
    puts "WARNING: Using #{seed}"
  end
  seed
end

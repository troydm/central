# -------------------------------------------------------------------------
# # central - dot files manager licensed under LGPLv3 (see LICENSE file)  |
# # written in Ruby by Dmitry Geurkov (d.geurkov@gmail.com)               |
# -------------------------------------------------------------------------

require 'erb'
require 'socket'
require 'open3'

# get hostname
def hostname
  Socket.gethostname
end

# get operating system
def os
  if RUBY_PLATFORM.include?('linux')
    return 'linux'
  elsif RUBY_PLATFORM.include?('darwin')
    return 'osx'
  elsif RUBY_PLATFORM.include?('freebsd')
    return 'freebsd'
  elsif RUBY_PLATFORM.include?('solaris')
    return 'solaris'
  end
end

def linux?
  return os == 'linux'
end

def osx?
  return os == 'osx'
end

def freebsd?
  return os == 'freebsd'
end

def solaris?
  return os == 'solaris'
end

# run shell command and get output, optionaly can print command running if verbose and if not silent will also print to stdout and stderr
$shell_return_value = nil
def shell(command,options={:verbose => false, :silent => true})
  silent = options[:silent]
  puts "Executing: #{command}" if options[:verbose]
  stdout = ''
  stdout_line = ''
  stderr = ''
  stderr_line = ''
  Open3.popen3(command) do |i,o,e,t|
    stdout_open = true
    stderr_open = true
    while stdout_open or stderr_open
      if stdout_open
        begin
          ch = o.read_nonblock(1)
          stdout.insert(-1,ch)
          unless silent
            stdout_line.insert(-1,ch)
            if ch == "\n"
              STDOUT.puts stdout_line
              stdout_line = ''
            end
          end
        rescue IO::WaitReadable
          IO.select([o],nil,nil,0.00001)
        rescue EOFError
          stdout_open = false
        end
      end
      if stderr_open
        begin
          ch = e.read_nonblock(1)
          stderr.insert(-1,ch)
          unless silent
            stderr_line.insert(-1,ch)
            if ch == "\n"
              STDERR.puts stderr_line
              stderr_line = ''
            end
          end
        rescue IO::WaitReadable
          IO.select([e],nil,nil,0.00001)
        rescue EOFError
          stderr_open = false
        end
      end
    end
    $shell_return_value = t.value
  end
  if stderr == ''
    return stdout
  else
    return stdout, stderr
  end
end

# run shell command with sudo prefix, acts same as shell
def sudo(command,options)
  return shell('sudo '+command, options)
end

# function used to check that system has all required tools installed
def check_tool(name,check)
  begin
    output = shell(check)
    if output.kind_of?(String)
      output = output.downcase
      if output == '' or output.include?('command not found')
        STDERR.puts "#{name} not found, please install it to use central"
        exit 1
      end
    elsif output.kind_of?(Array)
      if output[0] == '' and output[1] == ''
        STDERR.puts "#{name} not found, please install it to use central"
        exit 1
      end
    end
  rescue Errno::ENOENT
    STDERR.puts "#{name} not found, please install it to use central"
  end
end

check_tool('file','file --version')
check_tool('grep','grep --version')
check_tool('ln','ln --version')
check_tool('readlink','readlink --version')
check_tool('git','git --version')
check_tool('curl','curl --version')


# current working directory
def pwd
  Dir.pwd
end

# absolute path
def abs(path)
  path = File.absolute_path(File.expand_path(path))
end

# change current working directory
def chdir(dir)
  Dir.chdir(abs(dir))
end

# check if file exists
def file_exists?(path)
  path = abs(path)
  File.file?(path) && File.readable?(path)
end

# check if directory exists
def dir_exists?(path)
  path = abs(path)
  Dir.exists?(path)
end

# get directory name of a file
def file_dir(path)
  File.dirname(abs(path))
end

# check if file is symlink
def symlink?(symlink)
  File.symlink?(abs(symlink))
end

# get full path of symlink
def symlink_path(symlink)
  shell("readlink \"#{abs(symlink)}\"").strip
end

# make directory including intermediate directories
def mkdir(path)
  path = abs(path)
  unless dir_exists?(path)
    out = shell("mkdir -p \"#{path}\"")
    puts "Created directory: #{path}"
  end
end

# remove file/directory
def rm(path,recursive=false)
  path = abs(path)
  if recursive
    recursive = '-R '
  else
    recursive = ''
  end
  is_dir = dir_exists?(path)
  is_symlink = symlink?(path)
  out = shell("rm #{recursive}-f \"#{path}\"")
  if is_dir
    puts "Removed directory: #{path}"
  elsif is_symlink
    puts "Removed symlink: #{path}"
  else
    puts "Removed file: #{path}"
  end
end

# remove directory recursively
def rmdir(path)
  rm(path,true)
end

# touch file
def touch(path)
  path = abs(path)
  unless file_exists?(path)
    out = shell("touch \"#{path}\"")
    puts "Touched file: #{path}"
  end
end

# change file permissions
def chmod(path,permissions,recursive=false)
  path = abs(path)
  if recursive
    recursive = '-R '
  else
    recursive = ''
  end
  shell("chmod #{recursive}#{permissions} \"#{path}\"")
end

# symlink path
def symlink(from,to)
  from = abs(from)
  to = abs(to)
  if symlink?(from)
    if symlink_path(from) != to
      rm from
      symlink from, to
    end
  elsif file_exists?(from)
    STDERR.puts "File #{from} exists in place of symlink..."
    exit 1
  elsif dir_exists?(from)
    STDERR.puts "Directory #{from} exists in place of symlink..."
    exit 1
  else
    out = shell("ln -s \"#{to}\" \"#{from}\"")
    puts "Created symlink: #{from} → #{to}"
  end
end

# git clone url into a path
def git(url,path,branch=nil,silent=false)
  path = abs(path)
  if dir_exists?(path) && dir_exists?("#{path}/.git")
    cwd = pwd()
    chdir path
    out = nil
    if branch
      out = shell('git fetch',{:silent => silent})
      if out.size > 0
        puts out
      end
      out = shell("git checkout #{branch}",{:silent => silent})
      unless out.downcase.include? 'is now at'
        puts out
      end
      out = shell("git pull origin #{branch}",{:silent => silent})
    else
      out = shell('git pull',{:silent => silent})
    end
    unless out.downcase.include? "already up-to-date"
      puts out
      puts "Git repository pulled: #{url} → #{path}"
    end
    chdir cwd
  else
    if branch
      branch = "-b #{branch} "
    else
      branch = ''
    end
    out = shell("git clone #{branch}#{url} \"#{path}\"",{:silent => silent})
    puts out
    puts "Git repository cloned: #{url} → #{path}"
  end
end

# download url into a path using curl
def curl(url,path,verbose=false)
  path = abs(path)
  output = shell("curl -s -S \"#{url}\"",{:verbose => verbose, :silent => true})
  unless $shell_return_value.success?
    STDERR.puts "Couldn't download file from #{url}..."
    exit 1
  end
  if File.exists?(path) && File.read(path) == output
    return
  end
  File.write(path,output)
  puts "Downloaded #{url} → #{path}"
end

# read content of a file
def read(file)
  file = abs(file)
  if file_exists?(file)
    return File.read(file)
  else
    STDERR.puts "Couldn't read file #{file}..."
    exit 1
  end
end

# write content into a file
def write(file,content)
  file = abs(file)
  File.write(file,content)
end

# source file in sh/bash/zsh script
def source(file,source)
  file = abs(file)
  source = abs(source)
  source_line = "source \"#{source}\""
  out = shell("grep -Fx '#{source_line}' \"#{file}\"")
  if out == ""
    shell("echo '#{source_line}' >> \"#{file}\"")
    puts "Added source #{source} line to #{file}"
  end
end

# list directory content
def ls(path,options={})
  path = abs(path)
  if options[:dotfiles]
    dotfiles = '-a '
  else
    dotfiles = ''
  end
  command = "ls -1 #{dotfiles}\"#{path}\""
  if options.key?(:grep) && options[:grep].length > 0
    command += " | grep #{options[:grep]}"
  end
  output = shell(command)
  if output.downcase.end_with?('no such file or directory')
    STDERR.puts "Couldn't ls directory #{path}..."
    exit 1
  end
  ls = output.split("\n")
  dir = true
  file = true
  if options.key?(:dir)
    dir = options[:dir]
  end
  if options.key?(:file)
    file = options[:file]
  end
  unless dir
    ls = ls.keep_if {|f| !File.directory?("#{path}/#{f}") }
  end
  unless file
    ls = ls.keep_if {|f| !File.file?("#{path}/#{f}") }
  end
  return ls
end

# process erb template into an output_file
def erb(file,output_file = nil)
  file = abs(file)
  if output_file == nil
    if file.end_with?('.erb')
      output_file = file[0...-4]
    else
      output_file = file+'.out'
    end
  end
  if file_exists?(file)
    output = ERB.new(File.read(file)).result
    if File.exists?(output_file) && File.read(output_file) == output
      return
    end
    File.write(output_file,output)
    puts "Processed erb #{file} → #{output_file}"
  else
    STDERR.puts "Couldn't process erb file #{file}..."
    exit 1
  end
end

# run configuration.rb file
def run(file)
  cwd = pwd()
  file = abs(file)
  unless file_exists?(file)
    puts "No configuration file: #{file} found"
    return
  end
  puts "Running configuration: "+file
  file_cwd = file_dir(file)
  chdir file_cwd
  load file
  chdir cwd
end

# run configuration.rb file only if it exists
def run_if_exists(file)
  if file_exists?(file)
    run file
  end
end

# run central configuration
def central(configurations)
  if configurations.instance_of?(Array) && configurations.length > 0
    configurations.each {|configuration| run configuration }
  elsif configurations.instance_of?(String)
    run configurations
  else
    run 'configuration.rb'
  end
end


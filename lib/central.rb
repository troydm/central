# -------------------------------------------------------------------------
# # central - dot files manager licensed under LGPLv3 (see LICENSE file)  |
# # written in Ruby by Dmitry Geurkov (d.geurkov@gmail.com)               |
# -------------------------------------------------------------------------

require 'erb'
require 'socket'
require 'open3'
require 'fileutils'

# cli colors
COLOR_RED = 31
COLOR_GREEN = 32

# putsc, puts with color
def color(message, color)
  "\e[#{color}m#{message}\e[0m"
end

# info
def info(message, param = nil)
  puts color(message, COLOR_GREEN) +
       (param.nil? ? '' : ': ' + param)
end

# error
def error(message, param = nil)
  puts color(message, COLOR_RED) +
       (param.nil? ? '' : ': ' + param)
end

# fail, print message to stderr and exit with 1
def fail(message, param = nil)
  error message, param
  exit 1
end

# get hostname
def hostname
  Socket.gethostname
end

# get operating system
def os
  if RUBY_PLATFORM.include?('linux')
    'linux'
  elsif RUBY_PLATFORM.include?('darwin')
    'osx'
  elsif RUBY_PLATFORM.include?('freebsd')
    'freebsd'
  elsif RUBY_PLATFORM.include?('solaris')
    'solaris'
  end
end

def linux?
  os == 'linux'
end

def osx?
  os == 'osx'
end

def freebsd?
  os == 'freebsd'
end

def solaris?
  os == 'solaris'
end

# run shell command and get output, optionaly can print command running
# if verbose and if not silent will also print to stdout and stderr
def shell(command, verbose: false, silent: true)
  info 'Executing', command if verbose
  exit_code = nil
  stdout = ''
  stdout_line = ''
  stderr = ''
  stderr_line = ''
  Open3.popen3(command) do |_, o, e, t|
    stdout_open = true
    stderr_open = true
    while stdout_open || stderr_open
      if stdout_open
        begin
          ch = o.read_nonblock(1)
          stdout.insert(-1, ch)
          unless silent
            stdout_line.insert(-1, ch)
            if ch == "\n"
              STDOUT.puts stdout_line
              stdout_line = ''
            end
          end
        rescue IO::WaitReadable
          IO.select([o], nil, nil, 0.01) unless stderr_open
        rescue EOFError
          stdout_open = false
        end
      end
      next unless stderr_open

      begin
        ch = e.read_nonblock(1)
        stderr.insert(-1, ch)
        unless silent
          stderr_line.insert(-1, ch)
          if ch == "\n"
            STDERR.puts stderr_line
            stderr_line = ''
          end
        end
      rescue IO::WaitReadable
        IO.select([e], nil, nil, 0.01) unless stdout_open
      rescue EOFError
        stderr_open = false
      end
    end
    exit_code = t.value
  end
  [exit_code, stdout, stderr]
end

# run shell command with sudo prefix, acts same as shell
def sudo(command, verbose:, silent:)
  shell('sudo ' + command, verbose: verbose, silent: silent)
end

# function used to check that system has all required tools installed
def check_tool(name, check)
  _, output, = shell(check + ' 2>&1')
  if output == '' || output.downcase.include?('command not found')
    fail "#{name} not found, please install it to use central"
  end
rescue Errno::ENOENT
  fail "#{name} not found, please install it to use central"
end

check_tool('file', 'file --version')
check_tool('grep', 'grep --version')
check_tool('ln', 'ln --version')
check_tool('readlink', 'readlink --version')
check_tool('git', 'git --version')
check_tool('curl', 'curl --version')

# current working directory
def pwd
  Dir.pwd
end

# absolute path
def abs(path)
  File.absolute_path(File.expand_path(path))
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
  Dir.exist?(path)
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
  _, out, = shell("readlink \"#{abs(symlink)}\" 2>&1")
  out.strip
end

# make directory including intermediate directories
def mkdir(path)
  path = abs(path)
  return if dir_exists?(path)

  exit_code, out, = shell("mkdir -p \"#{path}\" 2>&1")
  unless exit_code.success?
    error out
    fail "Couldn't create directory", path
  end
  info 'Created directory', path
end

# remove file/directory
def rm(path, recursive: false)
  path = abs(path)
  recursive = recursive ? '-R ' : ''
  is_dir = dir_exists?(path)
  is_symlink = symlink?(path)
  exit_code, out, = shell("rm #{recursive}-f \"#{path}\" 2>&1")
  unless exit_code.success?
    error out
    fail "Couldn't remove path", path
  end
  if is_dir
    info 'Removed directory', path
  elsif is_symlink
    info 'Removed symlink', path
  else
    info 'Removed file', path
  end
end

# remove directory recursively
def rmdir(path)
  rm(path, recursive: true)
end

# touch file
def touch(path)
  path = abs(path)
  return if file_exists?(path)

  exit_code, out, = shell("touch \"#{path}\" 2>&1")
  unless exit_code.success?
    error out
    fail "Couldn't touch file", path
  end
  info 'Touched file', path
end

# change file permissions
def chmod(path, permissions, recursive: false)
  path = abs(path)
  recursive = recursive ? '-R ' : ''
  shell("chmod #{recursive}#{permissions} \"#{path}\"")
end

# symlink path
def symlink(from, to)
  from = abs(from)
  to = abs(to)
  if symlink?(from)
    if symlink_path(from) != to
      rm from
      symlink from, to
    end
  elsif file_exists?(from)
    fail "File #{from} exists in place of symlink..."
  elsif dir_exists?(from)
    fail "Directory #{from} exists in place of symlink..."
  else
    exit_code, out, = shell("ln -s \"#{to}\" \"#{from}\" 2>&1")
    unless exit_code.success?
      error out
      fail "Couldn't create symlink", "#{from} → #{to}"
    end
    info 'Created symlink', "#{from} → #{to}"
  end
end

# git clone url into a path
def git(url, path, branch: nil, silent: true, depth: nil)
  path = abs(path)
  if dir_exists?(path) && dir_exists?("#{path}/.git")
    cwd = pwd
    chdir path
    out = nil
    if branch
      _, out, = shell('git fetch 2>&1', silent: silent)
      puts out if silent && out.size.positive?
      _, out, = shell("git checkout #{branch} 2>&1", silent: silent)
      unless out.downcase.include? 'is now at'
        puts out if silent
      end
      _, out, = shell("git pull origin #{branch} 2>&1", silent: silent)
    else
      _, out, = shell('git pull 2>&1', silent: silent)
    end
    unless out.downcase.include? 'already up'
      puts out if silent
      info 'Git repository pulled', "#{url} → #{path}"
    end
    chdir cwd
  else
    branch = branch ? "-b #{branch} " : ''
    depth = depth ? "--depth #{depth} " : ''
    _, out, = shell("git clone #{depth}#{branch}#{url} \"#{path}\" 2>&1",
                    silent: silent)
    puts out if silent
    info 'Git repository cloned', "#{url} → #{path}"
  end
end

# download url into a path using curl
def curl(url, path, verbose: false)
  path = abs(path)
  info 'Downloading', "#{url} → #{path}"
  exit_code, output, = shell("curl -s -S \"#{url}\"",
                             verbose: verbose, silent: true)
  unless exit_code.success?
    error output
    fail "Couldn't download file from", url
  end
  File.write(path, output)
  info 'Downloaded', "#{url} → #{path}"
end

# read content of a file
def read(file)
  file = abs(file)
  return File.read(file) if file_exists?(file)

  fail "Couldn't read file", file
end

# write content into a file
def write(file, content)
  file = abs(file)
  File.write(file, content)
end

# source file in sh/bash/zsh script
def source(file, source)
  file = abs(file)
  source = abs(source)
  source_line = "source \"#{source}\""
  _, out, = shell("grep -Fx '#{source_line}' \"#{file}\"")
  return unless out == ''

  shell("echo '#{source_line}' >> \"#{file}\"")
  info 'Added source', "#{source} line to #{file}"
end

# list directory content
def ls(path, dotfiles: false, grep: '', dir: true, file: true)
  path = abs(path)
  dotfiles = dotfiles ? '-a ' : ''
  command = "ls -1 #{dotfiles}\"#{path}\" 2>&1"
  command += " | grep #{grep}" unless grep.empty?

  _, output, = shell(command)
  if output.downcase.end_with?('no such file or directory')
    fail "Couldn't ls directory", path
  end

  ls = output.split("\n")
  ls = ls.keep_if { |f| !File.directory?("#{path}/#{f}") } unless dir
  ls = ls.keep_if { |f| !File.file?("#{path}/#{f}") } unless file
  ls
end

# copy_file
def copy_file(from, to)
  fail "Couldn't access file", from unless file_exists?(from)

  return if file_exists?(to) && FileUtils.compare_file(from, to)

  FileUtils.copy_file(from, to)
  info 'Copied file', "#{from} → #{to}"
end

# copy
def copy(from, to)
  from = abs(from)
  to = abs(to)
  if dir_exists?(from)
    (Dir.entries(from).select { |f| f != '.' && f != '..' }).each do |f|
      FileUtils.mkdir_p(to)
      copy("#{from}/#{f}", "#{to}/#{f}")
    end
  else
    copy_file(from, to)
  end
end

# process erb template into an output_file
def erb(file, output_file = nil)
  file = abs(file)
  fail 'No erb file found', file unless file_exists?(file)

  if output_file.nil?
    output_file = file.end_with?('.erb') ? file[0...-4] : file + '.out'
  end
  out = ERB.new(File.read(file)).result
  return if File.exist?(output_file) && File.read(output_file) == out

  File.write(output_file, out)
  info 'Processed erb', "#{file} → #{output_file}"
end

# run configuration.rb file
def run(file)
  cwd = pwd
  file = abs(file)
  fail 'No configuration file found', file unless file_exists?(file)

  info 'Running configuration', file
  file_cwd = file_dir(file)
  chdir file_cwd
  load file
  chdir cwd
end

# run configuration.rb file only if it exists
def run_if_exists(file)
  run file if file_exists?(file)
end

# run central configuration
def central(configurations)
  if configurations.instance_of?(Array) && !configurations.empty?
    configurations.each { |configuration| run configuration }
  elsif configurations.instance_of?(String)
    run configurations
  else
    run 'configuration.rb'
  end
end

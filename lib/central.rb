# frozen_string_literal: true

# -------------------------------------------------------------------------
# # central - dot files manager licensed under LGPLv3 (see LICENSE file)  |
# # written in Ruby by Dmitry Geurkov (d.geurkov@gmail.com)               |
# -------------------------------------------------------------------------

require 'erb'
require 'socket'
require 'open3'
require 'fileutils'
require 'digest'

# options
$options = []

# get option, returns Array if multiple or nil if none
def option(opt)
  options = $options.filter { |option| option.index(opt) == 0 }
  if options.size == 0
    return nil
  elsif options.size == 1
    return options[0]
  else
    return options
  end
end

# cli colors
$colored = true
COLOR_RED = 31
COLOR_GREEN = 32

# monitors
$monitors = {}

# putsc, puts with color
def color(message, color)
  if $colored
    "\e[#{color}m#{message}\e[0m"
  else
    message
  end
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

def macos?
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
  stdout = String.new
  stderr = String.new
  Open3.popen3(command) do |_, o, e, t|
    stdout_open = true
    stderr_open = true
    while stdout_open || stderr_open
      if stdout_open
        begin
          buffer = o.read_nonblock(4096)
          stdout << buffer
          STDOUT.write(buffer) unless silent
        rescue IO::WaitReadable
          IO.select([o], nil, nil, 0.01) unless stderr_open
        rescue EOFError
          stdout_open = false
        end
      end
      next unless stderr_open

      begin
        buffer = e.read_nonblock(4096)
        stderr << buffer
        STDERR.write(buffer) unless silent
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

# get file size
def file_size(path)
  File.new(abs(path)).size
end

# get file creation time
def file_ctime(path)
  File.new(abs(path)).ctime
end

# get file modification time
def file_mtime(path)
  File.new(abs(path)).mtime
end

# get directory entries
def dir_entries(path)
  Dir.entries(abs(path)).select { |f| f != '.' && f != '..' }
end

# check if directory exists
def dir_exists?(path)
  path = abs(path)
  Dir.exist?(path)
end

# get file name of a path, optionally strip suffix if needed
def file_name(path, strip_suffix: '')
  File.basename(abs(path), strip_suffix)
end

# get file suffix of a path
def file_suffix(path)
  path = file_name(path)
  suffix_index = path =~ /\.[^.]+$/
  return path[suffix_index, path.size - suffix_index] if suffix_index
end

# get directory name of a path
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

# calculate SHA2 digest for a file
def sha2(file)
  Digest::SHA256.hexdigest read(file)
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

# extract archive, supports tar, zip, 7z
def extract(path, todir)
  path = abs(path)
  todir = abs(todir)
  unless file_exists?(path)
    fail "Archive file #{path} does not exists"
  end
  mkdir(todir)
  info 'Extracting archive', "#{path} → #{todir}"
  exit_code = nil, output = nil
  if path.end_with?('.zip')
    exit_code, output, = shell("unzip \"#{path}\" -d \"#{todir}\" 2>&1")
  elsif path.end_with?('.7z')
    exit_code, output, = shell("7z x -o\"#{todir}\" \"#{path}\" 2>&1")
  else
    exit_code, output, = shell("tar -xf \"#{path}\" -C \"#{todir}\" 2>&1")
  end
  unless exit_code.success?
    error output
    fail "Couldn't extract archive", path
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
def curl(url, path, content_length_check: false, verbose: false, flags: '-L -s -S')
  path = abs(path)
  if content_length_check and file_exists?(path)
    content_length = curl_headers(url, verbose: verbose, flags: flags)['content-length'].to_i
    return if file_size(path) == content_length
  end
  info 'Downloading', "#{url} → #{path}"
  exit_code, output, = shell("curl #{flags} \"#{url}\"",
                             verbose: verbose, silent: true)
  unless exit_code.success?
    error output
    fail "Couldn't download file from", url
  end
  File.write(path, output)
  info 'Downloaded', "#{url} → #{path}"
end

# get url response headers as Hash using curl
def curl_headers(url, method: 'HEAD', verbose: false, flags: '-L -s -S')
  exit_code, output, = shell("curl -I -X #{method} #{flags} \"#{url}\"",
                             verbose: verbose, silent: true)
  unless exit_code.success?
    error output
    fail "Couldn't get headers from", url
  end
  headers = {}
  output.scan(/^(?!HTTP)([^:]+):(.*)$/).each do |m|
    headers[m[0].strip.downcase] = m[1].sub("\r","").strip
  end
  headers
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

# compare_file
def compare_file(from, to)
  from = abs(from)
  to = abs(to)
  FileUtils.compare_file(from, to)
end

# copy_file
def copy_file(from, to)
  from = abs(from)
  to = abs(to)
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
    dir_entries(from).each do |f|
      FileUtils.mkdir_p(to)
      copy("#{from}/#{f}", "#{to}/#{f}")
    end
  else
    copy_file(from, to)
  end
end

# mirror
def mirror(from, to)
  from = abs(from)
  to = abs(to)
  if dir_exists?(from)
    from_entries = dir_entries(from)
    if dir_exists?(to)
      dir_entries(to).each do |f|
        rm("#{to}/#{f}", recursive: true) unless from_entries.include?(f)
      end
    end
    from_entries.each do |f|
      FileUtils.mkdir_p(to)
      copy("#{from}/#{f}", "#{to}/#{f}")
    end
  else
    copy_file(from, to)
  end
end

# process erb template into an output_file
def erb(file, output_file = nil, monitor = true)
  file = abs(file)
  fail 'No erb file found', file unless file_exists?(file)

  if output_file.nil?
    output_file = file.end_with?('.erb') ? file[0...-4] : file + '.out'
  end

  $monitors[file] = proc { erb(file, output_file, false) } if monitor

  out = ERB.new(File.read(file)).result
  return if File.exist?(output_file) && File.read(output_file) == out

  File.write(output_file, out)
  info 'Processed erb', "#{file} → #{output_file}"
end

# monitor file for changes and execute proc if file changed
def monitor(file, &block)
  file = abs(file)
  fail 'No file found', file unless file_exists?(file)

  $monitors[file] = block
end

# run configuration.rb file
def run(file)
  cwd = pwd
  file = abs(file)
  file = File.join(file,'configuration.rb') if not file_exists?(file) and dir_exists?(file)
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
def run_central(configurations, colored = true)
  $colored = colored
  if configurations.instance_of?(Array) && !configurations.empty?
    configurations.each { |configuration| run configuration }
  elsif configurations.instance_of?(String)
    run configurations
  else
    run 'configuration.rb'
  end
end

# run monitors
def run_monitors
  info 'Monitoring files for changes (press Ctrl-C to stop)'
  file_mtimes = {}
  $monitors.keys.each { |f| file_mtimes[f] = File.mtime(f) }
  loop do
    $monitors.keys.each do |f|
      file_mtime = File.mtime(f)
      next if file_mtime == file_mtimes[f]

      info 'File modified', f
      $monitors[f].call
      file_mtimes[f] = file_mtime
    end
    begin
      sleep(0.5)
    rescue Interrupt
      exit 0
    end
  end
end

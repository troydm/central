require 'minitest/autorun'
require 'central'

class CentralTest < Minitest::Unit::TestCase
  def test_os
    assert_includes ["linux", "osx", "freebsd", "solaris"], os
  end

  def test_pwd
    assert_equal Dir.pwd, pwd
  end

  def test_abs
    assert_equal ENV["HOME"], abs('~')
    assert_equal pwd, abs('.')
  end

  def test_chdir
    d = pwd
    chdir '~'
    assert_equal abs('~'), pwd
    chdir d
  end

  def test_file_exists?
    assert file_exists?('central.gemspec')
  end

  def test_dir_exists?
    assert dir_exists?('.')
  end

  def test_file_dir
    assert_equal pwd, file_dir('central.gemspec')
  end

  def test_file_name
    assert_equal 'central.gemspec', file_name('central.gemspec')
    assert_equal 'central.gemspec', file_name('/central.gemspec')
    assert_equal 'central.gemspec', file_name("#{pwd}/central.gemspec")
  end

  def test_file_suffix
    assert_equal '.gemspec', file_suffix('central.gemspec')
    assert_equal '.gemspec', file_suffix('central.another.gemspec')
    assert_equal nil, file_suffix('central')
  end

  def test_shell
    _, out, = shell('mkdir test/test-dir && ls -lh test && rmdir test/test-dir')
    assert_includes out, "test-dir"
  end

  def test_ls
    fs = ls('.')
    assert_includes fs, 'bin'
    assert_includes fs, 'lib'
    assert_includes fs, 'central.gemspec'
    fs = ls('.',dotfiles: true)
    assert_includes fs, '.gitignore'
    fs = ls('.', file: false)
    assert_includes fs, 'bin'
    assert_includes fs, 'lib'
    refute_includes fs, 'central.gemspec'
    fs = ls('.', dir: false)
    refute_includes fs, 'bin'
    refute_includes fs, 'lib'
    assert_includes fs, 'central.gemspec'
  end

  def test_symlink_functions
    refute symlink?('central.gemspec')
    symlink 'test/testlink', 'central.gemspec'
    assert symlink?('test/testlink')
    assert_equal abs('central.gemspec'), abs(symlink_path('test/testlink'))
    rm 'test/testlink'
    refute symlink?('test/testlink')
  end

  def test_dir_functions
    mkdir 'test/dir'
    assert dir_exists?('test/dir')
    rmdir 'test/dir'
    refute dir_exists?('test/dir')
  end

  def test_file_functions
    refute file_exists?('test/testfile')
    touch 'test/testfile'
    assert file_exists?('test/testfile')
    chmod 'test/testfile','0300'
    refute file_exists?('test/testfile')
    chmod 'test/testfile','0600'
    write 'test/testfile', 'testcontent'
    assert_equal 'testcontent', read('test/testfile')
    rm 'test/testfile'
    refute file_exists?('test/testfile')
  end

  def test_source
    touch 'test/testfile'
    touch 'test/testsource'
    source 'test/testsource', 'test/testfile'
    assert read('test/testsource').include?("source \""+abs('test/testfile')+"\"")
    content = read('test/testsource')
    source 'test/testsource', 'test/testfile'
    assert_equal content, read('test/testsource')
    rm 'test/testfile'
    rm 'test/testsource'
  end

  def test_copy
    f1 = "test/testfile1"
    f2 = "test/testfile2"
    write f1, "test"
    copy f1, f2
    assert_equal read(f1), read(f2)
    write f1, 'changed test'
    copy f1, f2
    assert_equal read(f1), read(f2)
    rm f1
    rm f2
  end

  def test_erb
    write 'test/testerb', "<%= 'hello' %>"
    erb 'test/testerb', 'test/testerboutput'
    assert_equal 'hello', read('test/testerboutput')
    rm 'test/testerb'
    rm 'test/testerboutput'
  end

  def test_sha2
    write 'test/test.txt', 'Some test data'
    assert_equal Digest::SHA256.hexdigest('Some test data'), sha2('test/test.txt')
    rm 'test/test.txt'
  end

  def test_compare_file
    write 'test/test1.txt', 'Some test data'
    write 'test/test2.txt', 'Some test data'
    assert_equal true, compare_file('test/test1.txt', 'test/test2.txt')
    write 'test/test2.txt', 'Some more test data'
    assert_equal false, compare_file('test/test1.txt', 'test/test2.txt')
    rm 'test/test1.txt'
    rm 'test/test2.txt'
  end

  def test_file_time_and_size
    write 'test/test.txt', 'Some test data'
    assert_equal true, file_size('test/test.txt') > 0
    assert_equal Time, file_ctime('test/test.txt').class
    assert_equal Time, file_mtime('test/test.txt').class
    rm 'test/test.txt'
  end

  def test_mirror
    mkdir 'test/testa'
    write 'test/testa/test1.txt', 'Some test data'
    mkdir 'test/testa/testb'
    write 'test/testa/testb/test2.txt', 'Some test data'
    mirror 'test/testa', 'test/testb'
    assert_equal Set.new(['test1.txt', 'testb']), Set.new(dir_entries('test/testb'))
    write 'test/testa/test1.txt', 'Some more test data'
    rm 'test/testa/testb', recursive: true
    mirror 'test/testa', 'test/testb'
    assert_equal Set.new(['test1.txt']), Set.new(dir_entries('test/testb'))
    assert_equal 'Some more test data', read('test/testb/test1.txt')
    rm 'test/testa', recursive: true
    rm 'test/testb', recursive: true
  end

  def test_curl
    curl 'https://github.com/', 'test/test.html'
    assert_equal true, file_size('test/test.html') > 0
    rm 'test/test.html'
  end

  def test_curl_headers
    assert_equal 'text/html; charset=utf-8', curl_headers('https://github.com/')['content-type']
  end
end


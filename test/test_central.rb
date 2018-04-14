require 'minitest/autorun'
require 'central'

class CentralTest < Minitest::Unit::TestCase
  def test_os
    assert_includes ["linux","osx","freebsd","solaris"], os
  end

  def test_pwd
    assert_equal Dir.pwd, pwd
  end

  def test_abs
    assert_equal ENV["HOME"], abs('~')
    assert_equal pwd, abs('.')
  end

  def test_chdir
    d = pwd()
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

  def test_shell
    out = shell('mkdir test/test-dir && ls -lh test && rmdir test/test-dir')
    assert_includes out, "test-dir"
  end

  def test_ls
    fs = ls('.')
    assert_includes fs, "bin"
    assert_includes fs, "lib"
    assert_includes fs, "central.gemspec"
    fs = ls('.',{:dotfiles => true})
    assert_includes fs, ".gitignore"
    fs = ls('.',{:dir => true, :file => false})
    assert_includes fs, "bin"
    assert_includes fs, "lib"
    refute_includes fs, "central.gemspec"
    fs = ls('.',{:dir => false, :file => true})
    refute_includes fs, "bin"
    refute_includes fs, "lib"
    assert_includes fs, "central.gemspec"
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
    write f1,"test"
    copy f1,f2
    assert_equal read(f1), read(f2)
    write f1,"changed test"
    copy f1,f2
    assert_equal read(f1), read(f2)
    rm f1
    rm f2
  end

  def test_erb
    write "test/testerb","<%= 'hello' %>"
    erb 'test/testerb','test/testerboutput'
    assert_equal "hello", read("test/testerboutput")
    rm 'test/testerb'
    rm 'test/testerboutput'
  end
end


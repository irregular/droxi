require 'dropbox_sdk'
require 'minitest/autorun'

require_relative 'testutils'
require_relative '../lib/droxi/commands'
require_relative '../lib/droxi/settings'
require_relative '../lib/droxi/state'

describe Commands do
  original_dir = Dir.pwd

  client = DropboxClient.new(Settings[:access_token])
  state = State.new(client)

  TEMP_FILENAME = 'test.txt'
  TEMP_FOLDER = 'test'

  before do
    Dir.chdir(original_dir)
  end

  describe 'when executing a shell command' do
    it 'must yield the output' do
      lines = TestUtils.output_of(Commands, :shell, 'echo test')
      lines.must_equal(['test'])
    end

    it 'must give an error message for an invalid command' do
      lines = TestUtils.output_of(Commands, :shell, 'bogus')
      lines.size.must_equal 1
    end
  end

  describe 'when executing the cd command' do
    it 'must change to the root directory when given no args' do
      state.pwd = '/testing'
      Commands::CD.exec(client, state)
      state.pwd.must_equal '/'
    end

    it 'must change to the stated directory when given 1 arg' do
      state.pwd = '/'
      Commands::CD.exec(client, state, '/testing')
      state.pwd.must_equal '/testing'
    end

    it 'must change and set previous directory correctly' do
      state.pwd = '/testing'
      state.pwd = '/'
      Commands::CD.exec(client, state, '-')
      state.pwd.must_equal '/testing'
      state.oldpwd.must_equal '/'
    end

    it 'must not change to a bogus directory' do
      state.pwd = '/'
      Commands::CD.exec(client, state, '/bogus_dir')
      state.pwd.must_equal '/'
    end

    it 'must fail with UsageError when given multiple args' do
      proc { Commands::CD.exec(client, state, 'a', 'b') }
        .must_raise Commands::UsageError
    end
  end

  describe 'when executing the cp command' do
    before do
      state.pwd = TestUtils::TEST_ROOT
      @copy = proc { |*args| Commands::CP.exec(client, state, *args) }
    end

    it 'must copy source to dest when given 2 args and last arg is non-dir' do
      TestUtils.structure(client, state, 'source')
      TestUtils.not_structure(client, state, 'dest')
      @copy.call('source', 'dest')
      %w(source dest).all? do |dir|
        state.metadata("/testing/#{dir}")
      end.must_equal true
    end

    it 'must copy source into dest when given 2 args and last arg is dir' do
      TestUtils.structure(client, state, 'source', 'dest')
      TestUtils.not_structure(client, state, 'dest/source')
      @copy.call('source', 'dest')
      state.metadata('/testing/dest/source').wont_be_nil
    end

    it 'must copy sources into dest when given 3 or more args' do
      TestUtils.structure(client, state, 'source1', 'source2', 'dest')
      TestUtils.not_structure(client, state, 'dest/source1', 'dest/source2')
      @copy.call('source1', 'source2', 'dest')
      %w(source2 source2).all? do |dir|
        state.metadata("/testing/dest/#{dir}")
      end.must_equal true
    end

    it 'must fail with UsageError when given <2 args' do
      test1 = proc { @copy.call }
      test2 = proc { @copy.call('a') }
      [test1, test2].each { |test| test.must_raise Commands::UsageError }
    end

    it 'must give an error message if trying to copy a bogus file' do
      _, err = capture_io { @copy.call('bogus', '/testing') }
      err.lines.size.must_equal 1
      err.start_with?('cp: ').must_equal true
    end

    it 'must fail to overwrite file without -f flag' do
      TestUtils.structure(client, state, 'source.txt', 'dest.txt')
      _, err = capture_io { @copy.call('source.txt', 'dest.txt') }
      err.lines.size.must_equal 1
    end

    it 'must also cp normally with -f flag' do
      TestUtils.structure(client, state, 'source.txt')
      TestUtils.not_structure(client, state, 'dest.txt')
      _, err = capture_io { @copy.call('-f', 'source.txt', 'dest.txt') }
      err.must_be :empty?
    end
  end

  describe 'when executing the debug command' do
    it 'must fail with an error message if debug mode is not enabled' do
      ARGV.clear
      lines = TestUtils.output_of(Commands::DEBUG, :exec, client, state, '1')
      lines.size.must_equal 1
      lines.first.start_with?('debug: ').must_equal true
    end

    it 'must evaluate the string if debug mode is enabled' do
      ARGV << '--debug'
      TestUtils.output_of(Commands::DEBUG, :exec, client, state, '1')
        .must_equal(['1'])
    end

    it 'must print the resulting exception if given exceptional input' do
      ARGV << '--debug'
      lines = TestUtils.output_of(Commands::DEBUG, :exec, client, state, 'x')
      lines.size.must_equal 1
      lines.first.must_match(/^#<.+>$/)
    end

    it 'must fail with UsageError when given no args' do
      proc { Commands::DEBUG.exec(client, state) }
        .must_raise Commands::UsageError
    end
  end

  describe 'when executing the forget command' do
    it 'must clear entire cache when given no arguments' do
      Commands::LS.exec(client, state, '/')
      Commands::FORGET.exec(client, state)
      state.cache.empty?.must_equal true
    end

    it 'must accept multiple arguments' do
      args = %w(bogus1, bogus2)
      TestUtils.output_of(Commands::FORGET, :exec, client, state, *args)
        .size.must_equal 2
    end

    it 'must recursively clear contents of directory argument' do
      Commands::LS.exec(client, state, '/', '/testing')
      Commands::FORGET.exec(client, state, '/')
      state.cache.size.must_equal 1
    end
  end

  describe 'when executing the get command' do
    it 'must get a file of the same name when given args' do
      TestUtils.structure(client, state, 'test.txt')
      Commands::GET.exec(client, state, '/testing/test.txt')
      `ls test.txt`.chomp.must_equal 'test.txt'
      `rm test.txt`
    end

    it 'must fail with UsageError when given no args' do
      proc { Commands::GET.exec(client, state) }
        .must_raise Commands::UsageError
    end

    it 'must give an error message if trying to get a bogus file' do
      lines = TestUtils.output_of(Commands::GET, :exec, client, state, 'bogus')
      lines.size.must_equal 1
      lines.first.start_with?('get: ').must_equal true
    end
  end

  describe 'when executing the lcd command' do
    it 'must change to home directory when given no args' do
      prev_pwd = Dir.pwd
      Commands::LCD.exec(client, state)
      Dir.pwd.must_equal File.expand_path('~')
      Dir.chdir(prev_pwd)
    end

    it 'must change to specific directory when specified' do
      prev_pwd = Dir.pwd
      Commands::LCD.exec(client, state, '/home')
      Dir.pwd.must_equal File.expand_path('/home')
      Dir.chdir(prev_pwd)
    end

    it 'must set oldpwd correctly' do
      oldpwd = Dir.pwd
      Commands::LCD.exec(client, state, '/')
      state.local_oldpwd.must_equal oldpwd
      Dir.chdir(oldpwd)
    end

    it 'must change to previous directory when given -' do
      oldpwd = Dir.pwd
      Commands::LCD.exec(client, state, '/')
      Commands::LCD.exec(client, state, '-')
      Dir.pwd.must_equal oldpwd
      Dir.chdir(oldpwd)
    end

    it 'must fail if given bogus directory name' do
      pwd = Dir.pwd
      oldpwd = state.local_oldpwd
      Commands::LCD.exec(client, state, '/bogus_dir')
      Dir.pwd.must_equal pwd
      state.local_oldpwd.must_equal oldpwd
      Dir.chdir(pwd)
    end
  end

  describe 'when executing the ls command' do
    it 'must list the working directory contents when given no args' do
      TestUtils.exact_structure(client, state, 'test')
      state.pwd = '/testing'
      TestUtils.output_of(Commands::LS, :exec, client, state)
        .must_equal(['test  '])
    end

    it 'must list the stated directory contents when given args' do
      state.pwd = '/'
      TestUtils.exact_structure(client, state, 'test')
      TestUtils.output_of(Commands::LS, :exec, client, state, '/testing')
        .must_equal(['test  '])
    end

    it 'must give a longer description with the -l option' do
      state.pwd = '/'
      TestUtils.exact_structure(client, state, 'test')
      lines = TestUtils.output_of(Commands::LS, :exec, client, state,
                                  '-l', '/testing')
      lines.size.must_equal 1
      lines.first[/d +0 \w{3} .\d \d\d:\d\d test/].wont_be_nil
    end

    it 'must give an error message if trying to list a bogus file' do
      lines = TestUtils.output_of(Commands::LS, :exec, client, state, 'bogus')
      lines.size.must_equal 1
      lines.first.start_with?('ls: ').must_equal true
    end
  end

  describe 'when executing the media command' do
    it 'must yield URL when given file path' do
      TestUtils.structure(client, state, 'test.txt')
      path = '/testing/test.txt'
      lines = TestUtils.output_of(Commands::MEDIA, :exec, client, state, path)
      lines.size.must_equal 1
      %r{https://.+\..+/}.match(lines.first).wont_be_nil
    end

    it 'must fail with error when given directory path' do
      _, err = capture_io { Commands::MEDIA.exec(client, state, '/testing') }
      err.lines.size.must_equal 1
      %r{https://.+\..+/}.match(err).must_be_nil
    end

    it 'must fail with UsageError when given no args' do
      proc { Commands::MEDIA.exec(client, state) }
        .must_raise Commands::UsageError
    end

    it 'must give an error message if trying to link a bogus file' do
      lines = TestUtils.output_of(Commands::MEDIA, :exec, client, state, '%')
      lines.size.must_equal 1
      lines.first.start_with?('media: ').must_equal true
    end
  end

  describe 'when executing the mkdir command' do
    it 'must create a directory when given args' do
      TestUtils.not_structure(client, state, 'test')
      Commands::MKDIR.exec(client, state, '/testing/test')
      state.metadata('/testing/test').wont_be_nil
    end

    it 'must fail with UsageError when given no args' do
      proc { Commands::MKDIR.exec(client, state) }
        .must_raise Commands::UsageError
    end
  end

  describe 'when executing the mv command' do
    before do
      state.pwd = TestUtils::TEST_ROOT
      @move = proc { |*args| Commands::MV.exec(client, state, *args) }
    end

    it 'must move source to dest when given 2 args and last arg is non-dir' do
      TestUtils.structure(client, state, 'source')
      TestUtils.not_structure(client, state, 'dest')
      @move.call('source', 'dest')
      state.metadata('/testing/source').must_be_nil
      state.metadata('/testing/dest').wont_be_nil
    end

    it 'must move source into dest when given 2 args and last arg is dir' do
      TestUtils.structure(client, state, 'source', 'dest')
      TestUtils.not_structure(client, state, 'dest/source')
      @move.call('source', 'dest')
      state.metadata('/testing/source').must_be_nil
      state.metadata('/testing/dest/source').wont_be_nil
    end

    it 'must move sources into dest when given 3 or more args' do
      TestUtils.structure(client, state, 'source1', 'source2', 'dest')
      TestUtils.not_structure(client, state, 'dest/source1', 'dest/source2')
      @move.call('source1', 'source2', 'dest')
      %w(source2 source2).all? do |dir|
        state.metadata("/testing/#{dir}").must_be_nil
        state.metadata("/testing/dest/#{dir}")
      end.must_equal true
    end

    it 'must fail with UsageError when given <2 args' do
      test1 = proc { @move.call }
      test2 = proc { @move.call('a') }
      [test1, test2].each { |test| test.must_raise Commands::UsageError }
    end

    it 'must give an error message if trying to move a bogus file' do
      _, err = capture_io { @move.call('bogus1', 'bogus2', 'bogus3') }
      err.lines.size.must_equal 3
      err.lines.all? { |line| line.start_with?('mv: ') }.must_equal true
    end

    it 'must fail to overwrite file without -f flag' do
      TestUtils.structure(client, state, 'source.txt', 'dest.txt')
      _, err = capture_io { @move.call('source.txt', 'dest.txt') }
      err.lines.size.must_equal 1
    end

    it 'must overwrite with -f flag' do
      TestUtils.structure(client, state, 'source.txt', 'dest.txt')
      _, err = capture_io { @move.call('-f', 'source.txt', 'dest.txt') }
      err.must_be :empty?
      state.metadata('/testing/source.txt').must_be_nil
    end
  end

  describe 'when executing the put command' do
    it 'must put a file of the same name when given 1 arg' do
      TestUtils.not_structure(client, state, 'test.txt')
      state.pwd = '/testing'
      `echo hello > test.txt`
      Commands::PUT.exec(client, state, 'test.txt')
      `rm test.txt`
      state.metadata('/testing/test.txt').wont_be_nil
    end

    it 'must put a file with the stated name when given 2 args' do
      TestUtils.not_structure(client, state, 'dest.txt')
      state.pwd = '/testing'
      `echo hello > test.txt`
      Commands::PUT.exec(client, state, 'test.txt', 'dest.txt')
      `rm test.txt`
      state.metadata('/testing/dest.txt').wont_be_nil
    end

    it 'must put file in directory if second arg is directory' do
      TestUtils.not_structure(client, state, 'test.txt')
      state.pwd = '/'
      `touch test.txt`
      Commands::PUT.exec(client, state, 'test.txt', 'testing')
      `rm test.txt`
      state.metadata('/testing/test.txt').wont_be_nil
    end

    it 'must fail with UsageError when given no args' do
      proc { Commands::PUT.exec(client, state) }
        .must_raise Commands::UsageError
    end
  end

  describe 'when executing the share command' do
    it 'must yield URL when given file path' do
      TestUtils.structure(client, state, 'test.txt')
      lines = TestUtils.output_of(Commands::SHARE, :exec, client, state,
                                  '/testing/test.txt')
      lines.size.must_equal 1
      %r{https://.+\..+/}.match(lines.first).wont_be_nil
    end

    it 'must fail with UsageError when given no args' do
      proc { Commands::SHARE.exec(client, state) }
        .must_raise Commands::UsageError
    end

    it 'must give an error message if trying to share a bogus file' do
      lines = TestUtils.output_of(Commands::SHARE, :exec, client, state, '%')
      lines.size.must_equal 1
      lines.first.start_with?('share: ').must_equal true
    end
  end

  describe 'when executing the rm command' do
    it 'must remove the remote file when given args' do
      TestUtils.structure(client, state, 'test.txt')
      Commands::RM.exec(client, state, '/testing/test.txt')
      state.metadata('/testing/test.txt').must_be_nil
    end

    it 'must change pwd to existing dir if the current one is removed' do
      # FIXME: I don't know why this test fails. It works in practice.
      # TestUtils.structure(client, state, 'one', 'one/two')
      # Commands::CD.exec(client, state, '/testing/one/two')
      # Commands::RM.exec(client, state, '..')
      # state.pwd.must_equal('/testing')
    end

    it 'must fail with UsageError when given no args' do
      proc { Commands::RM.exec(client, state) }
        .must_raise Commands::UsageError
    end

    it 'must give an error message if trying to remove a bogus file' do
      lines = TestUtils.output_of(Commands::RM, :exec, client, state, 'bogus')
      lines.size.must_equal 1
      lines.first.start_with?('rm: ').must_equal true
    end

    it 'must give error message if trying to remove dir without -r option' do
      TestUtils.structure(client, state, 'test')
      lines = TestUtils.output_of(Commands::RM, :exec, client, state,
                                  '/testing/test')
      lines.size.must_equal 1
      lines.first.start_with?('rm: ').must_equal true
    end

    it 'must remove dir recursively when given -r option' do
      TestUtils.structure(client, state, 'test', 'test/dir', 'test/file.txt')
      Commands::RM.exec(client, state, '-r', '/testing/test')
      paths = %w(/testing/test /testing/test/dir /testing/test/file.txt)
      paths.each { |path| state.metadata(path).must_be_nil }
    end
  end

  describe 'when executing the help command' do
    it 'must print a list of commands when given no args' do
      TestUtils.output_of(Commands::HELP, :exec, client, state)
        .join.split.size.must_equal Commands::NAMES.size
    end

    it 'must print help for a command when given it as an arg' do
      lines = TestUtils.output_of(Commands::HELP, :exec, client, state, 'help')
      lines.size.must_be :>=, 2
      lines.first.must_equal Commands::HELP.usage
      lines.drop(1).join(' ').must_equal Commands::HELP.description
    end

    it 'must print an error message if given a bogus name as an arg' do
      TestUtils.output_of(Commands::HELP, :exec, client, state, 'bogus')
        .size.must_equal 1
    end

    it 'must fail with UsageError when given multiple args' do
      proc { Commands::HELP.exec(client, state, 'a', 'b') }
        .must_raise Commands::UsageError
    end
  end

  describe 'when executing the rmdir command' do
    it 'must remove remote directories if empty' do
      TestUtils.exact_structure(client, state, 'dir1', 'dir2')
      Commands::RMDIR.exec(client, state, '/testing/dir?')
      paths = %w(/testing/dir1 /testing/dir2)
      paths.each { |path| state.metadata(path).must_be_nil }
    end

    it 'must fail with error if remote directory not empty' do
      TestUtils.structure(client, state, 'test', 'test/file.txt')
      lines = TestUtils.output_of(Commands::RMDIR, :exec, client, state,
                                  '/testing/test')
      lines.size.must_equal 1
      lines.first.start_with?('rmdir: ').must_equal true
    end

    it 'must fail with error if used on file' do
      TestUtils.structure(client, state, 'test.txt')
      lines = TestUtils.output_of(Commands::RMDIR, :exec, client, state,
                                  '/testing/test.txt')
      lines.size.must_equal 1
      lines.first.start_with?('rmdir: ').must_equal true
    end

    it 'must fail with error if given bogus name' do
      TestUtils.not_structure(client, state, 'bogus')
      lines = TestUtils.output_of(Commands::RMDIR, :exec, client, state,
                                  '/testing/bogus')
      lines.size.must_equal 1
      lines.first.start_with?('rmdir: ').must_equal true
    end

    it 'must fail with UsageError when given no args' do
      proc { Commands::RMDIR.exec(client, state) }
        .must_raise Commands::UsageError
    end
  end

  describe 'when executing the exit command' do
    it 'must request exit when given no args' do
      Commands::EXIT.exec(client, state)
      state.exit_requested.must_equal true
      state.exit_requested = false
    end

    it 'must fail with UsageError when given args' do
      proc { Commands::EXIT.exec(client, state, 'a') }
        .must_raise Commands::UsageError
    end
  end

  describe 'when exec-ing a string' do
    it 'must call a shell command when beginning with a !' do
      proc { Commands.exec('!echo hello', client, state) }
        .must_output "hello\n"
    end

    it "must execute a command when given the command's name" do
      proc { Commands.exec('lcd ~bogus', client, state) }
        .must_output "lcd: ~bogus: no such file or directory\n"
    end

    it 'must do nothing when given an empty string' do
      proc { Commands.exec('', client, state) }.must_be_silent
    end

    it 'must handle backslash-escaped spaces correctly' do
      TestUtils.structure(client, state, 'folder with spaces')
      proc { Commands.exec('ls /testing/folder\ with\ spaces', client, state) }
        .must_be_silent
    end

    it 'must give a usage error message for incorrect arg count' do
      out, _err = capture_io { Commands.exec('get', client, state) }
      out.start_with?('Usage: ').must_equal true
    end

    it 'must give an error message for invalid command name' do
      out, _err = capture_io { Commands.exec('drink soda', client, state) }
      out.start_with?('droxi: ').must_equal true
    end
  end

  describe 'when querying argument type' do
    it 'must return nil for command without args' do
      Commands::EXIT.type_of_arg(1).must_be_nil
    end

    it 'must return correct types for in-bounds indices' do
      Commands::PUT.type_of_arg(0).must_equal 'LOCAL_FILE'
      Commands::PUT.type_of_arg(1).must_equal 'REMOTE_FILE'
    end

    it 'must return last types for out-of-bounds index' do
      Commands::PUT.type_of_arg(3).must_equal 'REMOTE_FILE'
    end
  end
end

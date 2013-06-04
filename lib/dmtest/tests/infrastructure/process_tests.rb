require 'dmtest/process'
require 'dmtest/tags'
require 'test/unit'

#----------------------------------------------------------------

class ProcessTests < Test::Unit::TestCase
  include ProcessControl
  include Tags

  def setup
    ENV['THIN_TESTS'] = 'EXECUTE'
  end

  tag :infrastructure, :quick

  def test_true_succeeds
    ProcessControl.run('true')
  end

  def test_false_fails
    assert_raise(ExitError) do
      ProcessControl.run('false')
    end
  end

  def test_stdout_captured
    target_string = 'Hello, world!'
    output = ProcessControl.run("echo '#{target_string}'")
    assert_equal(output, target_string)
  end

  def test_stderr_captured
    assert_raise(ExitError) do
      ProcessControl.run("sed -e 's/badlyformed'")
    end
  end
end

require 'dmtest/prelude'
require 'dmtest/tags'

#----------------------------------------------------------------

class PreludeTests < Test::Unit::TestCase
  include Tags

  tag :quick, :infrastructure

  def test_bracket_normal_path
    tidied = false
    v = bracket(5, lambda {|n| tidied = true}) do |n|
      n + 1
    end

    assert_equal 6, v
    assert tidied
  end

  def test_bracket_fail_path
    tidied = false

    assert_raise(RuntimeError, 'bang!') do
      bracket(5, lambda {|n| tidied = true}) do |n|
        raise RuntimeError, 'bang!'
      end
    end

    assert tidied
  end

  def reset(_)
    @count = 0
  end

  def test_bracket_with_a_method
    @count = 4

    v = bracket(11, method(:reset)) do |c|
      @count = c
    end

    assert_equal v, 11
    assert_equal 0, @count
  end

  def test_bracket__normal_path
    tidied = false
    v = bracket_(lambda {tidied = true}) do
      5
    end

    assert_equal 5, v
    assert tidied
  end

  def test_bracket__fail
    tidied = false
    assert_raise(RuntimeError, 'bang!') do
      v = bracket_(lambda {tidied = true}) do
        raise RuntimeError, 'bang!'
      end
    end

    assert tidied
  end

  def test_protect_normal_path
    tidied = false
    v = protect(5, lambda {|n| tidied = true}) do |n|
      n + 1
    end

    assert_equal 6, v
    assert_equal false, tidied
  end

  def test_protect_fail_path
    tidied = false
    assert_raise(RuntimeError, 'bang!') do
      v = protect(5, lambda {|n| tidied = true}) do |n|
        raise RuntimeError, 'bang!'
      end
    end

    assert tidied
  end

  def test_protect__normal_path
    tidied = false
    v = protect_(lambda {tidied = true}) do
      5
    end

    assert_equal 5, v
    assert !tidied
  end

  def test_protect__fail_path
    tidied = false
    assert_raise(RuntimeError, 'bang!') do
      v = protect_(lambda {tidied = true}) do
        raise RuntimeError, 'bang!'
      end
    end

    assert tidied
  end
end

#----------------------------------------------------------------

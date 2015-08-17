require 'dmtest/thinp-mixin'

#----------------------------------------------------------------

module TestDetails
  class EvalOnce
    def initialize(thunk)
      @called = false
      @result = nil
      @thunk = thunk
    end

    def call
      if @called
        @result
      else
        @called = true
        @result = @thunk.call
      end
    end
  end
end

class ThinpTestCase < Test::Unit::TestCase
  undef_method :default_test
  include ThinpTestMixin

  def self.ensure_vars
    @requirements = @requirements || Hash.new([])
    @current_reqs = @current_reqs || []

    @tags = @tags || Hash.new([])
    @current_tags = @current_tags || []
  end

  def self.method_added(method)
    if method.to_s =~ /^test_/
      ensure_vars
      @requirements[method] = @current_reqs.dup
      @tags[method] = @current_tags
    end
  end

  def self.check_requirements(method)
    ensure_vars

    # Requirements will throw if they fail
    @requirements[method].each {|r| r.call}
  end

  def self.push_requirement(&block)
    ensure_vars
    @current_reqs << TestDetails::EvalOnce.new(block)
  end

  def self.pop_requirement
    ensure_vars
    @current_reqs.pop
  end

  def self.tag(*syms)
    @current_tags = syms
  end

  def get_tags(method)
    ensure_vars
    @tags[method]
  end
end

#----------------------------------------------------------------

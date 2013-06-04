require 'dmtest/thinp-mixin'

#----------------------------------------------------------------

class ThinpTestCase < Test::Unit::TestCase
  undef_method :default_test
  include ThinpTestMixin
end

#----------------------------------------------------------------

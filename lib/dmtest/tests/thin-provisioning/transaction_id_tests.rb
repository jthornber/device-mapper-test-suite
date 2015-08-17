require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/status'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class TransactionIdTests < ThinpTestCase
  include Utils
  extend TestUtils

  def trans_id(pool)
    PoolStatus.new(pool).transaction_id
  end

  def set_trans_id(pool, old, new)
    pool.message(0, "set_transaction_id #{old} #{new}")
  end

  define_test :initial_trans_id_is_zero do
    with_standard_pool(@size) do |pool|
      assert_equal 0, trans_id(pool)
    end
  end

  define_test :set_trans_id_works do
    with_standard_pool(@size) do |pool|
      0.upto(1000) do |n|
        set_trans_id(pool, n, n + 1)
      end
    end
  end

  define_test :set_trans_id_check_first_arg do
    with_standard_pool(@size) do |pool|
      assert_raise(ExitError) do
        set_trans_id(pool, 500, 1000)
      end

      assert_raise(ExitError) do
        set_trans_id(pool, 500, 0)
      end

      set_trans_id(pool, 0, 1234)

      assert_raise(ExitError) do
        set_trans_id(pool, 0, 1234)
      end

      set_trans_id(pool, 1234, 0)

      assert_raise(ExitError) do
        set_trans_id(pool, 1234, 0)
      end

      set_trans_id(pool, 0, 1234)
    end
  end
end

#----------------------------------------------------------------

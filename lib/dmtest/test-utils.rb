# Utils to help define tests
module TestUtils

  # We often want to define a set of tests with different start
  # parameters.  Rather than laboriously defining them all you can
  # just give this class method the sets of arguments you want to
  # range over and it'll define all the test methods for you.
  #
  # eg,
  #      define_test_across(:thin_on_striped, [1, 2, 3], [:ext4, :xfs])
  #
  # will define these tests
  #
  #      test_thin_on_striped_1_ext4
  #      test_thin_on_striped_1_xfs
  #      test_thin_on_striped_2_ext4
  #      test_thin_on_striped_2_xfs
  #      test_thin_on_striped_3_ext4
  #      test_thin_on_striped_3_xfs

  def define_tests_across(method, *args)
    cartprod(*args).each do |perm|
      method_name = "test_#{method}_#{perm.join('_')}"
      define_method(method_name) do
        send(method, *perm)
      end
    end
  end

  private
  def cartprod(*args)
    result = [[]]
    while [] != args
      t, result = result, []
      b, *args = args
      t.each do |a|
        b.each do |n|
          result << a + [n]
        end
      end
    end
    result
  end
end

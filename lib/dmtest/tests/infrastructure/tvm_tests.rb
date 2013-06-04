require 'dmtest/tvm'
require 'dmtest/tags'

#----------------------------------------------------------------

class TinyVolumeManagerTests < Test::Unit::TestCase
  include Tags
  include TinyVolumeManager

  tag :infrastructure, :quick

  def segment_total(segs)
    segs.inject(0) {|sum, s| sum + s.length}
  end

  def test_alloc_too_big_fails
    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume('little_disk', 0, 1000)
    assert_raise(RuntimeError) do
      tvm.add_volume(linear_vol('vol1', 1001))
    end
  end

  def test_alloc_all_space_succeeds
    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume('little_disk', 0, 1000)
    tvm.add_volume(linear_vol('vol1', 1000))

    assert_equal(segment_total(tvm.segments('vol1')), 1000)
  end

  def test_alloc_many_volumes
    tvm = VM.new
    tvm.add_allocation_volume('little_disk', 0, 1000)
    vols = 10

    1.upto(vols) do |i|
      tvm.add_volume(linear_vol("vol#{i}", 100))
    end

    1.upto(vols) do |i|
      assert_equal(segment_total(tvm.segments("vol#{i}")), 100)
    end
  end

  def test_allocate_release_cycle
    space = 1000000
    max_volume_size = 100000

    descs = Array.new
    count = 0
    s = space
    while s >= max_volume_size
      n = "vol#{count}"
      l = rand(max_volume_size)
      descs << linear_vol(n, l)
      s -= l
    end

    tvm = VM.new
    tvm.add_allocation_volume("disk", 0, space)
    10000.times do
      v = rand(descs.size)
      if tvm.member?(descs[v].name)
        tvm.remove_volume(descs[v].name)
      else
        tvm.add_volume(descs[v])
      end
    end
  end

  def test_remove_frees_space
    tvm = VM.new
    tvm.add_allocation_volume('little_disk', 0, 1000)

    1.upto(10) do |i|
      tvm.add_volume(linear_vol("vol#{i}", 100))
    end

    assert_equal(tvm.free_space, 0)

    1.upto(10) do |i|
      tvm.remove_volume("vol#{i}")
    end

    assert_equal(tvm.free_space, 1000)
  end

  def test_extend_linear_vol
    allocator = Allocator.new()
    allocator.release_segments(DevSegment.new('some_pv', 0, 1024))
    lv = Details::LinearVolume.new('volume', 100);
    lv.allocate(allocator)
    assert_equal(100, lv.length)
    assert_equal(100, segment_total(lv.segments))

    lv.resize(allocator, 101)
    assert_equal(101, lv.length)
    assert_equal(101, segment_total(lv.segments))

    lv.resize(allocator, 513)
    assert_equal(513, lv.length)
    assert_equal(513, segment_total(lv.segments))
  end

  def test_reduce_linear_vol
    allocator = Allocator.new()
    allocator.release_segments(DevSegment.new('some_pv', 0, 1024))
    lv = Details::LinearVolume.new('volume', 100);
    lv.allocate(allocator)
    assert_equal(100, lv.length)
    assert_equal(100, segment_total(lv.segments))

    # reduce isn't implemented yet
    assert_raise(RuntimeError) do
      lv.resize(allocator, 99)
    end

    # Nothing should have changed
    assert_equal(100, lv.length)
    assert_equal(100, segment_total(lv.segments))
  end
end

#----------------------------------------------------------------

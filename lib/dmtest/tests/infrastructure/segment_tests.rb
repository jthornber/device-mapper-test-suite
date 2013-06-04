require 'dmtest/segment'
require 'dmtest/tags'

#----------------------------------------------------------------

class SegmentTests < Test::Unit::TestCase
  include Tags
  include TinyVolumeManager

  tag :quick, :infrastructure

  def mk_seg(start, len)
    Segment.new(start, start + len)
  end

  def test_add_one_seg
    s = mk_seg(34, 100)

    segs = SegmentList.new
    segs.add(s)

    assert_equal(1, segs.count)
    assert_equal(s.length, segs.total)

    # remove the same seg
    segs.rm(s)

    assert_equal(0, segs.count)
    assert_equal(0, segs.total)
  end

  def test_multiple_segs
    ss = [mk_seg(34, 100),
          mk_seg(245, 17),
          mk_seg(1000, 34),
          mk_seg(2000, 34)]

    segs = SegmentList.new
    ss.each do |seg|
      segs.add(seg)
    end

    assert_equal(4, segs.count)
    assert_equal(185, segs.total)

    ss[1..-2].each do |seg|
      segs.rm(seg)
    end

    assert_equal(2, segs.count)
    assert_equal(134, segs.total)
  end

  def test_overlapping_segs1
    segs = SegmentList.new

    segs.add(mk_seg(34, 100))
    segs.add(mk_seg(50, 100))

    assert_equal(1, segs.count)
    assert_equal(116, segs.total)
  end

  def test_overlapping_segs2
    segs = SegmentList.new

    segs.add(mk_seg(5, 10))
    segs.add(mk_seg(3, 14))

    assert_equal(1, segs.count)
    assert_equal(14, segs.total)
  end

  def test_overlapping_segs3
    segs = SegmentList.new

    segs.add(mk_seg(50, 100))
    segs.add(mk_seg(34, 100))

    assert_equal(1, segs.count)
    assert_equal(116, segs.total)
  end

  def test_zero_length_segments
    segs = SegmentList.new
    segs.add(mk_seg(34, 0))
    assert_equal(0, segs.count)
    assert_equal(0, segs.total)
  end

  def test_first_policy
    segs = SegmentList.new
    segs.add(mk_seg(34, 100))
    segs.add(mk_seg(300, 10))
    s = segs.alloc(AllocPolicy::First.new)
    assert_equal(34, s.begin)
    assert_equal(134, s.end)
    assert_equal(1, segs.count)
    assert_equal(10, segs.total)
  end

  def test_last_policy
    segs = SegmentList.new
    segs.add(mk_seg(34, 100))
    segs.add(mk_seg(300, 10))
    s = segs.alloc(AllocPolicy::Last.new)
    assert_equal(300, s.begin)
    assert_equal(310, s.end)
    assert_equal(1, segs.count)
    assert_equal(100, segs.total)
  end

  def prepare_sl
    segs = SegmentList.new
    [mk_seg(1, 1),
     mk_seg(10, 2),
     mk_seg(20, 5),
     mk_seg(30, 20)].each {|s| segs.add(s)}
    segs
  end

  def test_best_fit_policy1
    segs = prepare_sl
    s = segs.alloc(AllocPolicy::BestFit.new(1))
    assert_equal(1, s.begin)
    assert_equal(1, s.length)
    assert_equal(3, segs.count)
    assert_equal(27, segs.total)
  end

  def test_best_fit_policy2
    segs = prepare_sl
    s = segs.alloc(AllocPolicy::BestFit.new(2))
    assert_equal(10, s.begin)
    assert_equal(2, s.length)
    assert_equal(3, segs.count)
    assert_equal(26, segs.total)
  end

  def test_best_fit_policy3
    segs = prepare_sl
    s = segs.alloc(AllocPolicy::BestFit.new(100))
    assert_equal(30, s.begin)
    assert_equal(20, s.length)
    assert_equal(3, segs.count)
    assert_equal(8, segs.total)
  end

  def test_best_fit_policy4
    segs = prepare_sl
    s = segs.alloc(AllocPolicy::BestFit.new(11))
    assert_equal(30, s.begin)
    assert_equal(20, s.length)
    assert_equal(3, segs.count)
    assert_equal(8, segs.total)
  end

  def test_best_fit_policy5
    segs = SegmentList.new
    assert_raise(RuntimeError) do
      s = segs.alloc(AllocPolicy::BestFit.new(100))
    end
  end
end

require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/blktrace'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/snapshot_utils'
require 'dmtest/snapshot_stack'
require 'concurrent'
require 'tempfile'
require 'erb'

#----------------------------------------------------------------

class FIOConfig < Hash
  def initialize(template, config={})
    super()

    @template = template
    self.update(config)
  end

  def update_io_limits(dev_size, nr_workers)
    self[:numjobs] = nr_workers
    self[:size] = dev_size / nr_workers
    self[:offset_increment] = (nr_workers == 1) ? 0 : self[:size]
  end

  def render
    b = binding

    self.each do |key, val|
      b.local_variable_set(key.to_sym, val)
    end

    ERB.new(@template, nil, "-").result(b)
  end

  def save
    cfgfile = Tempfile.new(["fio-job-", ".ini"])
    begin
      cfgfile.write(render)
    ensure
      cfgfile.close
    end

    cfgfile
  end
end

class FIOTests < ThinpTestCase
  include Utils
  include BlkTrace
  include DiskUnits
  include SnapshotUtils
  extend TestUtils

  PERSISTENT = [:N, :P]

  def setup
    super

    @origin_size = gig(80)
    @chunk_size = k(4)
    @max_workers = 8

    max_snap_size = max_snapshot_size(@origin_size, @chunk_size, :P)
    total_size = @origin_size + max_snap_size

    if dev_size(@data_dev) < total_size
      raise "Data device #{@data_dev} must be at least #{total_size} sectors to run this class of tests"
    end
  end

  def run_fio(config)
    cfgfile = config.save
    begin
      info("Running fio with config:\n#{config.render}")
      ProcessControl.run("fio #{cfgfile.path}")
    ensure
      cfgfile.unlink
    end
  end

  def iter_workers(max_workers)
    nr_workers = 1
    loop do
      yield nr_workers

      nr_workers *= 2
      break if nr_workers > max_workers
    end
  end

  def do_benchmark(rw, bs, type, run_bench, *args)
    if (type == :throughput)
      template = File.read(LP("tests/snapshot/fio_throughput.config.erb"))
    elsif (type == :latency)
      template = File.read(LP("tests/snapshot/fio_latency.config.erb"))
    else
      raise "Unknown benchmark type `#{type}'"
    end

    cfg = FIOConfig.new(template, :rw => rw, :bs => bs,
                        :cpus_allowed => "0-#{Concurrent.processor_count - 1}")

    iter_workers(@max_workers) do |nr_workers|
      run_bench.call(nr_workers, cfg, *args)
    end
  end

  #------------------------------------------------
  # dm-snapshot-origin throughput and latency tests
  #------------------------------------------------
  def fio_origin(nr_workers, config, persistent)
    snapshot_size = max_snapshot_size(@origin_size, @chunk_size, persistent)
    config.update_io_limits(@origin_size * 512, nr_workers)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @origin_size)
    s.activate do
      s.with_new_snap(0, snapshot_size, persistent, @chunk_size) do |snap|
        config[:filename] = s.origin
        run_fio(config)
      end
    end
  end

  def fio_origin_trace(nr_workers, config, persistent)
    blktrace_cpu_io_distribution(@data_dev) do
      fio_origin(nr_workers, config, persistent)
    end
  end

  def fio_origin_randwrite_throughput(persistent)
    do_benchmark("randwrite", "4K", :throughput, method(:fio_origin),
                 persistent)
  end

  define_tests_across(:fio_origin_randwrite_throughput, PERSISTENT)

  def fio_origin_randwrite_iod(persistent)
    do_benchmark("randwrite", "4K", :throughput, method(:fio_origin_trace),
                 persistent)
  end

  define_tests_across(:fio_origin_randwrite_iod, PERSISTENT)

  def fio_origin_randwrite_latency(persistent)
    do_benchmark("randwrite", "4K", :latency, method(:fio_origin), persistent)
  end

  define_tests_across(:fio_origin_randwrite_latency, PERSISTENT)

  def fio_origin_seqwrite_throughput(persistent)
    do_benchmark("write", "256K", :throughput, method(:fio_origin), persistent)
  end

  define_tests_across(:fio_origin_seqwrite_throughput, PERSISTENT)

  def fio_origin_seqwrite_iod(persistent)
    do_benchmark("write", "256K", :throughput, method(:fio_origin_trace),
                 persistent)
  end

  define_tests_across(:fio_origin_seqwrite_iod, PERSISTENT)

  #-----------------------------------------
  # dm-snapshot throughput and latency tests
  #-----------------------------------------
  def fio_snapshot(nr_workers, config, persistent)
    snapshot_size = max_snapshot_size(@origin_size, @chunk_size, persistent)
    config.update_io_limits(@origin_size * 512, nr_workers)

    s = SnapshotStack.new(@dm, @data_dev, :origin_size => @origin_size)
    s.activate do
      s.with_new_snap(0, snapshot_size, persistent, @chunk_size) do |snap|
        config[:filename] = snap
        run_fio(config)
      end
    end
  end

  def fio_snapshot_trace(nr_workers, config, persistent)
    blktrace_cpu_io_distribution(@data_dev) do
      fio_snapshot(nr_workers, config, persistent)
    end
  end

  def fio_snapshot_randwrite_throughput(persistent)
    do_benchmark("randwrite", "4K", :throughput, method(:fio_snapshot),
                 persistent)
  end

  define_tests_across(:fio_snapshot_randwrite_throughput, PERSISTENT)

  def fio_snapshot_randwrite_iod(persistent)
    do_benchmark("randwrite", "4K", :throughput, method(:fio_snapshot_trace),
                 persistent)
  end

  define_tests_across(:fio_snapshot_randwrite_iod, PERSISTENT)

  def fio_snapshot_randwrite_latency(persistent)
    do_benchmark("randwrite", "4K", :latency, method(:fio_snapshot), persistent)
  end

  define_tests_across(:fio_snapshot_randwrite_latency, PERSISTENT)

  def fio_snapshot_seqwrite_throughput(persistent)
    do_benchmark("write", "256K", :throughput, method(:fio_snapshot),
                 persistent)
  end

  define_tests_across(:fio_snapshot_seqwrite_throughput, PERSISTENT)

  def fio_snapshot_seqwrite_iod(persistent)
    do_benchmark("write", "256K", :throughput, method(:fio_snapshot_trace),
                 persistent)
  end

  define_tests_across(:fio_snapshot_seqwrite_iod, PERSISTENT)

  def fio_snapshot_randread_throughput(persistent)
    do_benchmark("randread", "4K", :throughput, method(:fio_snapshot),
                 persistent)
  end

  define_tests_across(:fio_snapshot_randread_throughput, PERSISTENT)

  def fio_snapshot_randread_latency(persistent)
    do_benchmark("randread", "4K", :latency, method(:fio_snapshot), persistent)
  end

  define_tests_across(:fio_snapshot_randread_latency, PERSISTENT)

  def fio_snapshot_seqread_throughput(persistent)
    do_benchmark("read", "256K", :throughput, method(:fio_snapshot), persistent)
  end

  define_tests_across(:fio_snapshot_seqread_throughput, PERSISTENT)

  #---------------------------------------------------
  # Raw device throughput and latency tests (baseline)
  #---------------------------------------------------
  def fio_raw_device(nr_workers, config)
    config[:filename] = @data_dev
    config.update_io_limits(dev_size(@data_dev) * 512, nr_workers)
    run_fio(config)
  end

  def fio_raw_device_trace(nr_workers, config)
    blktrace_cpu_io_distribution(@data_dev) do
      fio_raw_device(nr_workers, config)
    end
  end

  define_test :fio_raw_device_randwrite_throughput do
    do_benchmark("randwrite", "4K", :throughput, method(:fio_raw_device))
  end

  define_test :fio_raw_device_randwrite_iod do
    do_benchmark("randwrite", "4K", :throughput, method(:fio_raw_device_trace))
  end

  define_test :fio_raw_device_randwrite_latency do
    do_benchmark("randwrite", "4K", :latency, method(:fio_raw_device))
  end

  define_test :fio_raw_device_seqwrite_throughput do
    do_benchmark("write", "256K", :throughput, method(:fio_raw_device))
  end

  define_test :fio_raw_device_seqwrite_iod do
    do_benchmark("write", "256K", :throughput, method(:fio_raw_device_trace))
  end

  define_test :fio_raw_device_randread_throughput do
    do_benchmark("randread", "4K", :throughput, method(:fio_raw_device))
  end

  define_test :fio_raw_device_randread_latency do
    do_benchmark("randread", "4K", :latency, method(:fio_raw_device))
  end

  define_test :fio_raw_device_seqread_throughput do
    do_benchmark("read", "256K", :throughput, method(:fio_raw_device))
  end
end

#----------------------------------------------------------------

require 'thinp_xml/cache_xml'

#----------------------------------------------------------------

module CacheUtils
  include Utils
  include DiskUnits
  extend TestUtils
  include CacheXML
  include ThinpXML

  # FIXME: lose this and get people to use CacheStack directly
  def make_stack(overrides = Hash.new)
    block_size = overrides.fetch(:block_size, @data_block_size)
    cache_size = overrides.fetch(:cache_blocks, @cache_blocks) * block_size

    opts = {
      :cache_size => cache_size,
      :block_size => block_size,
      :format => true,
      :data_size => meg(128),
      :policy => Policy.new('mq')
    }

    CacheStack.new(@dm, @metadata_dev, @data_dev, opts.merge(overrides))
  end

  def wait_for_all_clean(cache)
    tid = Thread.new(cache) do |cache|
      loop do
        sleep(1)
        status = CacheStatus.new(cache)
        STDERR.puts "#{status.nr_dirty} dirty blocks"
        break if status.nr_dirty == 0
      end
    end

    cache.event_tracker.wait(cache) do |cache|
      status = CacheStatus.new(cache)
      status.nr_dirty == 0
    end

    tid.join
  end

  # FIXME: ditto, or is there a CacheMetadata < Device abstraction?
  def dump_metadata(dev)
    output = ProcessControl.run("cache_dump #{dev}")
    read_xml(StringIO.new(output))
  end

  def make_mappings_dirty(mappings)
    mappings.map! {|m| m.dirty = true; m}
  end

  def make_mappings_clean(mappings)
    mappings.map! {|m| m.dirty = false; m}
  end
end

#----------------------------------------------------------------

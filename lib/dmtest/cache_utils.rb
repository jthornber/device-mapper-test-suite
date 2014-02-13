require 'thinp_xml/cache_xml'

#----------------------------------------------------------------

module CacheUtils
  include Utils
  include DiskUnits
  extend TestUtils
  include CacheXML
  include ThinpXML

  # This function _is_ a mixin 
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

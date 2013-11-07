require 'thinp_xml/cache_xml'

#----------------------------------------------------------------

module CacheUtils
  include Utils
  include DiskUnits
  extend TestUtils
  include CacheXML
  include ThinpXML

  # FIXME: move to a utils module
  def make_stack(overrides = Hash.new)
    cache_size = overrides.fetch(:cache_blocks, @cache_blocks) * @data_block_size

    opts = {
      :cache_size => cache_size,
      :block_size => @data_block_size,
      :format => true,
      :data_size => meg(128),
      :policy => Policy.new('mq')
    }

    CacheStack.new(@dm, @metadata_dev, @data_dev, opts.merge(overrides))
  end

  def prepare_populated_cache(overrides = Hash.new)
    md = nil

    nr_blocks = overrides.fetch(:cache_blocks, @cache_blocks)

    dirty_percentage = overrides.fetch(:dirty_percentage, 0)
    dirty_flag = "--dirty-percent #{dirty_percentage}"

    clean_shutdown = overrides.fetch(:clean_shutdown, true)
    omit_shutdown_flag = clean_shutdown ? '' : "--omit-clean-shutdown"

    xml_file = 'metadata.xml'
    ProcessControl.run("cache_xml create --nr-cache-blocks #{nr_blocks} --nr-mappings #{nr_blocks} #{dirty_flag} > #{xml_file}")

    s = make_stack(overrides)
    s.activate_support_devs do
      ProcessControl.run("cache_restore #{omit_shutdown_flag} -i #{xml_file} -o #{s.md}")
      md = dump_metadata(s.md)
    end

    md
  end

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

#----------------------------------------------------------------

module DM
  class Target
    attr_accessor :type, :args, :sector_count

    def initialize(t, sector_count, *args)
      @type = t
      @sector_count = sector_count
      @args = args
    end
  end

  #--------------------------------

  class ErrorTarget < Target
    def initialize(sector_count)
      super('error', sector_count)
    end
  end

  #--------------------------------

  class FlakeyTarget < Target
    def initialize(sector_count, dev, offset = 0, up_interval = 60, down_interval = 0, drop_writes = false)
      extra_opts = Array.new
      extra_opts.instance_eval do
        push :drop_writes if drop_writes
      end

      super('flakey', sector_count, dev, offset, up_interval, down_interval, extra_opts.length, *extra_opts)
    end
  end

  #--------------------------------

  class LinearTarget < Target
    def initialize(sector_count, dev, offset)
      super('linear', sector_count, dev, offset)
    end
  end

  #--------------------------------

  class StripeTarget < Target
    def initialize(sector_count, chunk_size, *pairs)
      super('striped', sector_count, chunk_size, *(pairs.flatten))
    end
  end

  #--------------------------------

  class ThinPoolTarget < Target
    attr_accessor :metadata_dev

    def initialize(sector_count, metadata_dev, data_dev, block_size, low_water_mark,
                   zero = true, discard = true, discard_pass = true, read_only = false,
                   error_if_no_space = false)
      extra_opts = Array.new

      extra_opts.instance_eval do
        push :skip_block_zeroing unless zero
        push :ignore_discard unless discard
        push :no_discard_passdown unless discard_pass
        push :read_only if read_only
        push :error_if_no_space if error_if_no_space
      end

      super('thin-pool', sector_count, metadata_dev, data_dev, block_size, low_water_mark, extra_opts.length, *extra_opts)
      @metadata_dev = metadata_dev
    end

    def post_remove_check
      ProcessControl.run("thin_check #{@metadata_dev}")
    end
  end

  #--------------------------------

  class ThinTarget < Target
    def initialize(sector_count, pool, id, origin = nil)
      if origin
        super('thin', sector_count, pool, id, origin)
      else
        super('thin', sector_count, pool, id)
      end
    end
  end

  #--------------------------------

  class CacheTarget < Target
    attr_reader :metadata_dev

    def initialize(sector_count, metadata_dev, cache_dev, origin_dev, block_size, features,
                   policy, keys)
      args = [metadata_dev, cache_dev, origin_dev, block_size, features.size] +
        features.map {|f| f.to_s} + [policy, 2 * keys.size] + keys.map {|k, v| [k.to_s.sub(/_\d$/, "")] + [v.to_s]}

      super('cache', sector_count, *args)
      @metadata_dev = metadata_dev
    end

    def post_remove_check
      ProcessControl.run("cache_check #{@metadata_dev}")
    end
  end

  #--------------------------------

  class EraTarget < Target
    def initialize(sector_count, metadata_dev, origin_dev, block_size)
      super('era', sector_count, metadata_dev, origin_dev, block_size)
      @metadata_dev = metadata_dev
    end

    def post_remove_check
      ProcessControl.run("era_check #{@metadata_dev}")
    end
  end

  #--------------------------------

  class FakeDiscardTarget < Target
    def initialize(sector_count, dev, offset, granularity, max_discard,
                   no_discard_support = false, discard_zeroes = false)
      extra_opts = Array.new

      extra_opts.instance_eval do
        push :no_discard_support if no_discard_support
        push :discard_zeroes_data if discard_zeroes
      end

      super('fake-discard', sector_count, dev, offset, granularity,
            max_discard, extra_opts.length, *extra_opts)
    end
  end

  #--------------------------------

  class RaidTarget < Target
    # We don't do validation of the params here, since some tests may
    # want to deliberately pass bad params.
    def initialize(sector_count, params, dev_pairs)
      devs = []
      devs.each do |p|
        devs << p[0]
        devs << p[1]
      end

      super('raid', params.size, *params, dev_pairs.size, devs);
    end
  end

  #--------------------------------

  class SnapshotTarget < Target
    def initialize(sector_count, origin, cow_dev, persistent, chunk_size)
      super('snapshot', sector_count, origin, cow_dev, persistent, chunk_size)
    end
  end

  #--------------------------------

  class SnapshotOriginTarget < Target
    def initialize(sector_count, origin)
      super('snapshot-origin', sector_count, origin)
    end
  end

  #--------------------------------

  class SnapshotMergeTarget < Target
    def initialize(sector_count, origin, cow_dev, persistent, chunk_size)
      super('snapshot-merge', sector_count, origin, cow_dev, persistent,
            chunk_size)
    end
  end
end

#----------------------------------------------------------------

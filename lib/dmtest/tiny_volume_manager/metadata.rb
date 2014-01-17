require 'rubygems'
require 'active_record'
require 'logger'

# I'm having trouble with the gem version, so copied file to debug.
# Possibly because I'm using the Debian packaged version of gem?
require 'dmtest/acts_as_tree'
require 'dmtest/device-mapper/dm'

#----------------------------------------------------------------

module Metadata
  include ActiveRecord

  class MetadataStore
    def initialize(params)
      setup_logging
      connect(params)
      setup_schema
    end

    def close
    end

    def setup_logging
      ActiveRecord::Base.logger = Logger.new(File.open('sql.log', 'w'))
    end

    def connect(params)
      @db = ActiveRecord::Base.establish_connection(params)
    end

    def setup_schema
      # FIXME: check the range of the :integer fields

      ActiveRecord::Schema.define do
        create_table :volumes do |t|
          t.column :name, :string
          t.column :uuid, :string
        end

        create_table :segments, :force => true do |t|
          t.column :offset, :integer
          t.column :length, :integer
          t.column :volume_id, :integer
          t.column :parent_id, :integer
          t.column :target_id, :integer
          t.column :target_type, :string
        end

        # This covers linear targets too
        create_table :striped_targets do |t|
          t.column :nr_stripes, :integer
        end

        create_table :pool_targets do |t|
          t.column :metadata_id, :integer
          t.column :data_id, :integer
          t.column :block_size, :integer
          t.column :low_water_mark, :integer
          t.column :block_zeroing, :bool
          t.column :discard, :bool
          t.column :discard_passdown, :bool
          t.column :error_if_no_space, :bool
          t.column :blocks_per_allocation, :integer
        end

        create_table :thin_targets do |t|
          t.column :pool_id, :integer
          t.column :dev_id, :integer
          t.column :origin_id, :integer
        end
      end
    end    
  end

  class Volume < Base
    has_many :segments

    def to_s
      "#{self.name}: #{self.uuid}"
    end

    def length
      ss = segments
      if ss.length == 0
        0
      else
        last = ss[-1]
        last.offset + last.length
      end
    end

    def is_pv?
      segments.all? {|s| s.target.nil?}
    end
  end

  class Segment < Base
    belongs_to :volume
    acts_as_tree :order => :offset
    belongs_to :target, :polymorphic => true

    def to_s
      "#{self.volume.name} [#{self.offset} #{self.length}]"
    end
  end

  module TargetMethods
    def uuid_to_path(uuid)
      uuid
    end
  end

  class StripedTarget < Base
    include TargetMethods

    has_one :segment, :as => :target

    def to_s
      if self.nr_stripes == 1
        "linear"
      else
        "#{self.nr_stripes} stripes"
      end
    end

    def deps
      []
    end

    def to_dm_target
      if nr_stripes == 1
        if children.length != 1
          raise "incorrect number of child segments for a linear target"
        end

        c = children[0]
        LinearTarget.new(length, uuid_to_path(c.volume.uuid), c.offset)
      else
        raise "not implemented"
      end
    end
  end

  class PoolTarget < Base
    include TargetMethods

    has_one :segment, :as => :target
    belongs_to :metadata_dev, :class_name  => Volume, :foreign_key => :metadata_id
    belongs_to :data_dev, :class_name => Volume, :foreign_key => :data_id

    def to_s
      "Pool: md => #{self.metadata_dev.name}, data => #{self.data_dev.name}"
    end

    def deps
      [self.metadata_dev, self.data_dev]
    end

    def to_dm_target
      DM::ThinPoolTarget.new(0, #length,
                             metadata_dev.name,
                             data_dev.name,
                             block_size,
                             low_water_mark,
                             block_zeroing,
                             discard,
                             discard_passdown,
                             error_if_no_space,
                             blocks_per_allocation)
    end
  end

  class ThinTarget < Base
    include TargetMethods

    has_one :segment, :as => :target
    belongs_to :pool, :class_name => Volume, :foreign_key => :pool_id

    def to_s
      "Thin: pool => #{self.pool.name}, dev_id => #{self.dev_id}"
    end

    def deps
      [pool]
    end

    def to_dm_target
      DM::ThinTarget.new(0, "/dev/mapper/#{pool.name}", dev_id)
    end
  end
end

#----------------------------------------------------------------

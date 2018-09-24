require 'dmtest/prelude'
require 'dmtest/device_mapper'
require 'dmtest/ensure_elapsed'

module DM
  # This mixin assumes there is a dm_interface method returns a DMInterface

  # FIXME: the post_remove_check should be lifted from dev
  module LexicalOperators
    include EnsureElapsed

    def with_dev(table = nil, &block)
      bracket(create_dev(table),
              lambda {|dev| dev.remove; dev.post_remove_check}) do |dev|
        ensure_elapsed_time(1, dev, &block)
      end
    end

    def with_ro_dev(table = nil, &block)
      bracket(create_dev(table, true),
              lambda {|dev| dev.remove; dev.post_remove_check}) do |dev|
        ensure_elapsed_time(1, dev, &block)
      end
    end

    def with_devs(*tables, &block)
      release = lambda do |devs|
        devs.reverse.each do |dev|
          begin
            dev.remove
            dev.post_remove_check
          rescue
          end
        end
      end

      bracket(Array.new, release) do |devs|
        tables.each do |table|
          devs << create_dev(table)
        end

        ensure_elapsed_time(1, devs, &block)
      end
    end

    def create_dev(table = nil, read_only = false)
      path = create_path
      tidy = lambda {dm_interface.remove(path)}

      dm_interface.create(path)
      protect_(tidy) do
        dev = DMDev.new(path, dm_interface)
        unless table.nil?
          if read_only
            dev.load_ro(table)
          else
            dev.load(table)
          end
          dev.resume
        end
        dev
      end
    end

    private
    def create_path
      # fixme: check this device doesn't already exist
      "/dev/mapper/test-dev-#{rand(1000000)}"
    end
  end
end

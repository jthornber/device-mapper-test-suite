# Edit this file to add your setup

module Config
  # You can now configure different profiles for a machine.  Add the
  # profile name after a colon to the hash key, and then run with the
  # -p switch.
  # eg,
  #   ./run_tests --profile mix -t /Basic/

  CONFIGS = {
    # ejt's machines
    'vm4:ssd' => {
      :metadata_dev => '/dev/vdb', # SSD
      :data_dev => '/dev/vdc',     # SSD
      :mass_fs_tests_parallel_runs => 3,
    },

    'vm4:spindle' => {
      :metadata_dev => '/dev/vdd', # spindle
      :data_dev => '/dev/vde',     # spindle
      :mass_fs_tests_parallel_runs => 3,
    },

    'vm4:mix' => {
      :metadata_dev => '/dev/vdb', # SSD
      :data_dev => '/dev/vde',     # spindle
      :mass_fs_tests_parallel_runs => 3,
    },

    'vm3.vm-network' => {
      :metadata_dev => '/dev/vdb', # SSD
      :data_dev => '/dev/vdc',     # SSD
      :mass_fs_tests_parallel_runs => 3,
    },

    'vm3.vm-network:mix' => {
      :metadata_dev => '/dev/vdb', # SSD
      :data_dev => '/dev/vde',     # Spindle
      :data_size => 1097152 * 2 * 10,
      :volume_size => 1097152 * 2,
      :mass_fs_tests_parallel_runs => 3,
    },

    'vm3.vm-network:spindle' => {
      :metadata_dev => '/dev/vdd', # Spindle
      :data_dev => '/dev/vde',     # Spindle
      :data_size => 1097152 * 2 * 10,
      :volume_size => 1097152 * 2,
      :mass_fs_tests_parallel_runs => 3
    },

    'vm-debian-32' =>
    { :metadata_dev => '/dev/sdc',
      :data_dev => '/dev/sdd'
    },

    # others ...
    's6500.ww.redhat.com' =>
    { :metadata_dev => '/dev/loop1',
      :metadata_size => 32768,
      :data_dev => '/dev/loop0',
      :data_size => 6696048,
      :volume_size => 1097152,
      :data_block_size => 128,
      :low_water_mark => 1
    },


    'a4.ww.redhat.com' =>
    { # :metadata_dev => '/dev/tst/cache_1way',
      # :metadata_dev => '/dev/tst/cache',
      # :metadata_dev => '/dev/tst/cache_1way_same',
      :metadata_dev => '/dev/mapper/skd0',
      :metadata_size => 32768,
      # :data_dev => '/dev/skd0',
      :data_dev => '/dev/vg_a4/origin',
      # :data_dev => '/dev/tst/data_ssd',
      # :data_dev => '/dev/tst/data_ssd_striped',
      # :data_dev => '/dev/tst/dual_spindle_linear_sde+sdf',
      :data_size => 283115520,
      :volume_size => 70377, # 2097152,
      :data_block_size => 524288,
      :low_water_mark => 5,
      :mass_fs_tests_parallel_runs => 128,
      :cache_policies => %w|multiqueue fifo|
      # :cache_policies => %w|mq multiqueue q2 twoqueue fifo filo lru mru lfu mfu|
    }

  }

  def Config.get_config
    host = `hostname --fqdn`.chomp

    if $profile
      host = "#{host}:#{$profile}"
    end

    if CONFIGS.has_key?(host)
      CONFIGS[host]
    else
      raise RuntimeError, "unknown host '#{host}', set up your config in config.rb"
    end
  end
end

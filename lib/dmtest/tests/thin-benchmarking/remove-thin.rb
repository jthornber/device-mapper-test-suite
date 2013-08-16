require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/xml_format'

#----------------------------------------------------------------

class RemoveThinTests < ThinpTestCase
  include Utils

  def test_benchmark_remove_thin
    xml_file = 'big.xml'
    nr_thins = 30
    block_size = 128

#    [20000, 40000, 60000, 80000, 100000, 120000, 140000, 200000].each do |nr_mappings|
    [1000000].each do |nr_mappings|
      ProcessControl.run("thinp_xml create --nr-thins #{nr_thins} --nr-mappings #{nr_mappings} --block-size #{block_size} > #{xml_file}")
      ProcessControl.run("thin_restore -o #{@metadata_dev} -i #{xml_file}")

      with_error_pool(nr_thins * nr_mappings * block_size) do |pool|
        report_time("delete thin volume '#{nr_mappings}'", STDERR) do
          pool.message(0, "delete 0")
        end
      end
    end
  end
end

#----------------------------------------------------------------

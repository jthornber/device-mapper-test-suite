require 'dmtest/log'

#----------------------------------------------------------------

class PoolStatus
  attr_reader :transaction_id, :used_metadata_blocks, :total_metadata_blocks, :used_data_blocks
  attr_reader :total_data_blocks, :held_root, :options, :fail

  def parse_held_root(txt)
    case txt
    when '-' then
        nil

    else
      txt.to_i
    end
  end

  def parse_opts(txt)
    opts = Hash.new
    opts[:block_zeroing] = true
    opts[:ignore_discard] = false
    opts[:discard_passdown] = true
    opts[:read_only] = false
    opts[:error_if_no_space] = false

    txt.strip.split.each do |feature|
      case feature
      when 'skip_block_zeroing' then
        opts[:block_zeroing] = false

      when 'ignore_discard' then
        opts[:ignore_discard] = true

      when 'no_discard_passdown' then
        opts[:discard_passdown] = false

      when 'discard_passdown' then
        opts[:discard_passdown] = true

      when 'ro' then
        opts[:read_only] = true

      when 'rw' then
        opts[:read_only] = false

      when 'error_if_no_space' then
        opts[:error_if_no_space] = true

      when 'queue_if_no_space' then
        opts[:error_if_no_space] = false

      else
        raise "unknown pool feature '#{feature}'"
      end
    end

    opts
  end

  def initialize(pool)
    status = pool.status
    m = status.match(/(\d+)\s(\d+)\/(\d+)\s(\d+)\/(\d+)\s(\S+)(\s.*)/)
    if m.nil?
      # it's possible the pool's fallen back to failure mode
      if status.match(/\s*Fail\s*/)
        @fail = true
      else
        raise "couldn't get pool status"
      end
    else
      @fail = false
      @transaction_id = m[1].to_i
      @used_metadata_blocks = m[2].to_i
      @total_metadata_blocks = m[3].to_i
      @used_data_blocks = m[4].to_i
      @total_data_blocks = m[5].to_i
      @held_root = parse_held_root(m[6])
      @options = parse_opts(m[7])
    end
  end
end

#----------------------------------------------------------------

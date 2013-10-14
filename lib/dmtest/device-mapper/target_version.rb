#----------------------------------------------------------------

module DM
  class TargetVersion
    attr_accessor :major, :minor, :patch

    RX = /^v(\d+).(\d+).(\d+)$/

    def initialize(str)
      m = RX.match(str)

      raise "badly formed target version string '#{str}'" if !m
      @major = m[1].to_i
      @minor = m[2].to_i
      @patch = m[3].to_i
    end

    def ==(rhs)
      @major == rhs.major && @minor == rhs.minor && @patch == rhs.patch
    end
  end

  def parse_version_lines(txt)
    result = {}

    rx = /(\S+)\s+(\S+)/
    txt.lines.each do |line|
      m = rx.match(line)

      raise "badly formed version line: '#{line}'" if !m
      result[m[1]] = TargetVersion.new(m[2])
    end

    result
  end

  def get_target_versions
    parse_version_lines(ProcessControl.run('dmsetup targets'))
  end
end

#----------------------------------------------------------------

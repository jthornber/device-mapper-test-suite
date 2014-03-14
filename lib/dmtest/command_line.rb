require 'ejt_command_line'

#----------------------------------------------------------------

DMTestCommandLine = CommandLine::Parser.new do
  value_type :string do |str|
    str
  end

  value_type :symbol do |str|
    str.intern
  end

  value_type :int do |str|
    Integer(str)
  end

  FILTER_PATTERN = %r{\A/(.*)/\Z}

  value_type :filter do |str|
    m = FILTER_PATTERN.match(str)
    if m
      pattern = Regexp.new(m[1])
      lambda do |name|
        pattern =~ name ? true : nil
      end
    else
      lambda do |name|
        str == name ? true : nil
      end
    end
  end

  simple_switch :help, '-h', '--help'
  simple_switch :tags, '--tags'
  multivalue_switch :name, :filter, '-n', '--name'
  multivalue_switch :testcase, :filter, '-t'
  value_switch :profile, :symbol, '--profile'
  value_switch :suite, :string, '--suite'
  value_switch :port, :int, '--port'

  command :help do
  end

  command :run do
    switches :name, :profile, :suite, :testcase
  end

  command :list do
    switches :name, :suite, :testcase, :tags
  end

  command :serve do
    switches :port
  end

  command :generate do
  end

  global do
    switches :help
  end
end

#----------------------------------------------------------------

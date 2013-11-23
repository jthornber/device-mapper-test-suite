require_relative 'version'

module DMTest
  module Utils
    # The template files live in the gems lib directory.  We want to
    # be able to read them whether we're running as an installed gem,
    # or from the local dir (via bundle exec).
    def self.gem_libdir
      ($:).each do |i|
        gem_dir = "#{i}/#{DMTest::NAME}"
        return gem_dir if File.readable?(gem_dir)
      end

      raise "Couldn't find gem lib dir"
    end
  end
end

module Utils
  # Library Path
  def LP(path)
    DMTest::Utils.gem_libdir + "/" + path
  end

  # Absolute Path
  ROOTDIR = Pathname.new(".").realpath.to_s
  def AP(path)
    ROOTDIR + "/" + path
  end
end

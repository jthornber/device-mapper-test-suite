module DM
  class Table
    attr_accessor :targets

    def initialize(*targets)
      @targets = targets
    end

    def size
      @targets.inject(0) {|tot, t| tot += t.sector_count}
    end

    def to_s()
      start_sector = 0

      @targets.map do |t|
        r = "#{start_sector} #{t.sector_count} #{t.type} #{t.args.join(' ')}"
        start_sector += t.sector_count
        r
      end.join("\n")
    end

    def to_embed_
      start_sector = 0

      @targets.map do |t|
        r = "#{start_sector} #{t.sector_count} #{t.type} #{t.args.join(' ')}"
        start_sector += t.sector_count
        r
      end.join("; ")
    end

    def to_embed
      "<<table:#{to_embed_}>>"
    end
  end
end

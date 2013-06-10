# Copyright (C) 2010 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing to use,
# modify, copy, or redistribute it subject to the terms and conditions
# of the GNU General Public License v.2.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Policy for the location of report templates
require 'dmtest/report-generators/string-store'
require 'dmtest/report-generators/reports'

require_relative '../../dmtest/libdir'

class TemplateStringStore < StringStore
  def initialize()
    super([DMTest::Utils.gem_libdir + '/report-generators/templates'])
  end
end

module DMTest
  class ReportGenerator
    include Reports

    def initialize(output_dir)
      @output_dir = output_dir
    end

    def unit_detail(t)
      generate_report(:unit_detail, binding,
                      Pathname.new("#{@output_dir}/#{mangle(t.suite + "__" + t.name)}.html"))
    end

    def unit_summary(all_tests)
      suites = all_tests.group_by {|t| t.suite}

      total_passed = all_tests.inject(0) {|tot, t| tot + (t.pass? ? 1 : 0)}
      total_failed = all_tests.length - total_passed

      generate_report(:unit_test, binding,
                      Pathname.new("#{@output_dir}/index.html"))
    end

    def stylesheet
      generate_report(:stylesheet, binding,
                      Pathname.new("#{@output_dir}/stylesheet.css"))
    end

    private
    def generate_report(report, bs, dest_path)
      reports = ReportRegister.new
      template_store = TemplateStringStore.new
      report = reports.get_report(report)
      erb = ERB.new(template_store.lookup(report.template))
      body = erb.result(bs)
      title = report.short_desc

      erb = ERB.new(template_store.lookup("boiler_plate.rhtml"))
      txt = erb.result(binding)

      dest_path.open("w") do |out|
        out.puts txt
      end
    end

    # Formats dm tables
    def expand_tables(txt)
      txt.gsub(/<<table:([^>]*)>>/) do |match|
        output = '</pre><table width="95%" cellspacing="0" cellpadding="0" border="0" class="stripes">'
        $1.split(/;\s*/).each do |line|
          m = /(\d+)\s+(\d+)\s+(\S+)\s+(.*)/.match(line)
          raise RuntimeError, "badly formatted table line" if !m
          output << "<tr><td><pre>#{m[1]}</pre></td><td><pre>#{m[2]}</pre></td><td><pre>#{m[3]}</pre></td><td><pre>#{m[4]}</pre></td></tr>"
        end
        output << '</table><pre>'
      end
    end

    def expand_message(msg)
      "<tr class=\"#{msg.level}\"><td><pre>#{msg.level}</pre></td><td><pre>#{msg.time}</pre></td><td><pre>#{expand_tables(msg.txt)}</pre></td></tr>"
    end

    def safe_mtime(r)
      r.path.file? ? r.path.mtime.to_s : "not generated"
    end
  end
end

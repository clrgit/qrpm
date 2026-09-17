require 'open3'
require 'tmpdir'
require 'yaml'

describe "qrpm executable" do
  EXE = File.expand_path("../exe/qrpm", __dir__)

  def qrpm(*args, chdir: Dir.pwd)
    Open3.capture3("ruby", EXE, *args, chdir: chdir)
  end

  around(:each) do |example|
    Dir.mktmpdir { |dir|
      @dir = dir
      example.run
    }
  end

  attr_reader :dir

  describe "--help" do
    let(:help) { qrpm("--help").first }

    it "lists 'require' as a standard variable" do
      expect(help).to match(/^\s*require$/)
      expect(help).not_to match(/^\s*requires$/)
    end

    it "lists the RPM fields" do
      Qrpm::FIELDS.keys.each { |field|
        next if field == "include" # Described in its own section
        next if field == "group" # Not documented, it is not needed on current RPM systems
        expect(help).to match(/^\s*#{field}$/), "#{field} is not documented"
      }
    end
  end

end

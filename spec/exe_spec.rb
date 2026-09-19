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

  describe "--template" do
    it "generates a template file" do
      stdout, stderr, status = qrpm("-t", chdir: dir)
      expect(status).to be_success, stderr
      expect(File).to exist "#{dir}/qrpm.yml"
      expect(stdout).to include "Generated qrpm.yml"
    end

    it "refuses to overwrite an existing file" do
      File.write "#{dir}/qrpm.yml", ""
      _stdout, stderr, status = qrpm("-t", chdir: dir)
      expect(status).not_to be_success
      expect(stderr).to include "Won't overwrite existing file"
    end

    it "overwrites an existing file with --force-template" do
      File.write "#{dir}/qrpm.yml", ""
      _stdout, stderr, status = qrpm("-T", chdir: dir)
      expect(status).to be_success, stderr
      expect(File.size("#{dir}/qrpm.yml")).to be > 0
    end
  end

  describe "--help" do
    let(:help) { qrpm("--help").first }

    it "lists 'require' as a standard variable" do
      expect(help).to match(/^\s*require$/)
      expect(help).not_to match(/^\s*requires$/)
    end

    it "lists the RPM fields" do
      Qrpm::FIELDS.keys.each { |field|
        next if field == "include" # Described in its own section
        expect(help).to match(/^\s*#{field}$/), "#{field} is not documented"
      }
    end
  end

  describe "--target" do
    def write_qrpm_file
      File.write "#{dir}/qrpm.yml", { "name" => "pck", "version" => "1.0.0", "summary" => "s" }.to_yaml
    end

    it "builds a spec for the target" do
      write_qrpm_file
      _stdout, stderr, status = qrpm("--target=el7", "-s", chdir: dir)
      expect(status).to be_success, stderr
      spec = File.read("#{dir}/pck.spec")
      expect(spec).to start_with "%global _binary_payload w9.gzdio\n"
      expect(spec).to include "Release: 1.el7\n"
    end

    it "rejects unknown targets" do
      write_qrpm_file
      _stdout, stderr, status = qrpm("--target=el5", "-s", chdir: dir)
      expect(status).not_to be_success
      expect(stderr).to include "Unknown target 'el5'"
    end
  end

  describe "show" do
    it "outputs directory variables without double slashes" do
      # Only variables used by a directory are evaluated and can be shown
      yaml = {
        "name" => "pck", "version" => "1.0.0", "summary" => "s",
        "$sysetcdir" => ["etc/file"], "$pckvardir" => ["var/file"]
      }
      File.write "#{dir}/qrpm.yml", yaml.to_yaml
      stdout, stderr, status = qrpm("show", "qrpm.yml", "sysetcdir", "pckvardir", chdir: dir)
      expect(status).to be_success, stderr
      expect(stdout).to eq "/etc\n/var/lib/pck\n"
    end
  end
end

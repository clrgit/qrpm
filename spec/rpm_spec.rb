require 'open3'

describe "Qrpm::Rpm" do
  # Compile a qrpm.yml hash and render the SPEC file
  def render(yaml)
    yaml = { "name" => "pck", "version" => "1.0.0", "summary" => "summary" }.merge(yaml)
    Qrpm::Compiler.new({}).compile(yaml).rpm.render
  end

  describe "#render" do
    it "renders the spec file without building" do
      spec = render({})
      expect(spec).to match(/^Name: pck$/)
      expect(spec).to match(/^Version: 1.0.0$/)
    end

    it "does not emit double slashes in paths" do
      spec = render("$bindir" => ["bin/file"], "$pcketcdir" => ["etc/file"])
      expect(spec).not_to include "//"
      expect(spec).to include "%{buildroot}/usr/bin"
      expect(spec).to include "/etc/pck/file"
    end
  end
end

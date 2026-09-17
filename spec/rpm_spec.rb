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

    it "does not emit a Group tag" do
      expect(render({})).not_to match(/^Group:/)
    end

    it "does not emit double slashes in paths" do
      spec = render("$bindir" => ["bin/file"], "$pcketcdir" => ["etc/file"])
      expect(spec).not_to include "//"
      expect(spec).to include "%{buildroot}/usr/bin"
      expect(spec).to include "/etc/pck/file"
    end

    it "emits one ln line per symlink" do
      spec = render("$sbindir" => [
          { "symlink" => "/usr/bin/first" },
          { "symlink" => "/usr/bin/second" }
      ])
      expect(spec).to include "ln -sf /usr/bin/first /usr/sbin/first"
      expect(spec).to include "ln -sf /usr/bin/second /usr/sbin/second"
    end

    it "emits one ln line per reflink" do
      spec = render("$sbindir" => [
          { "reflink" => "/usr/bin/first" },
          { "reflink" => "/usr/bin/second" }
      ])
      expect(spec).to include "ln -sf /usr/bin/first /usr/sbin/first"
      expect(spec).to include "ln -sf /usr/bin/second /usr/sbin/second"
    end

    it "sets permissions using %attr instead of chmod" do
      spec = render("$bindir" => [{ "file" => "bin/file", "perm" => "0600" }])
      expect(spec).to include "%attr(0600,-,-) /usr/bin/file"
      expect(spec).not_to include "chmod"
    end

    it "emits files without perm as plain paths" do
      spec = render("$bindir" => ["bin/file"])
      expect(spec).to match(/^\/usr\/bin\/file$/)
      expect(spec).not_to include "%attr"
    end
  end
end

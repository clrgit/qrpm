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

    describe "routines" do
      it "emits make in %build" do
        spec = render("make" => "make all\n")
        expect(spec).to include "%build\ncd .\nmake all\n"
      end
      it "emits pre, post, pre_uninstall, and post_uninstall as scriptlets" do
        spec = render("pre" => "echo pre", "post" => "echo post",
                      "pre_uninstall" => "echo preun", "post_uninstall" => "echo postun")
        expect(spec).to include "%pre\necho pre\n"
        expect(spec).to include "%post\necho post\n"
        expect(spec).to include "%preun\necho preun\n"
        expect(spec).to include "%postun\necho postun\n"
      end
      it "emits generated link commands before post" do
        spec = render("post" => "echo post", "$sbindir" => [{ "symlink" => "/usr/bin/file" }])
        expect(spec).to include "%post\nln -sf /usr/bin/file /usr/sbin/file\necho post\n"
      end
      it "omits scriptlets that are not defined" do
        spec = render({})
        expect(spec).not_to include "%pre\n"
        expect(spec).not_to include "%preun"
        expect(spec).not_to include "%postun"
      end
      it "defines referenced qrpm variables at the top of the script" do
        spec = render("post" => "mkdir -p $pckvardir\nchown $owner ${pckvardir}\n", "owner" => "some one")
        expect(spec).to include "%post\npckvardir=/var/lib/pck\nowner=some\\ one\nmkdir -p $pckvardir\n"
      end
      it "leaves shell variables, positional parameters, and commands alone" do
        spec = render("post" => "echo $HOME $1 ${2:-x} $(hostname)\n")
        expect(spec).to include "%post\necho $HOME $1 ${2:-x} $(hostname)\n"
      end
      it "keeps the indentation of the script" do
        spec = render("post" => "if true; then\n  echo x\nfi\n")
        expect(spec).to include "if true; then\n  echo x\nfi\n"
      end
    end
  end
end

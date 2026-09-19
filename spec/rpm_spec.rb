require 'open3'

describe "Qrpm::Rpm" do
  # Compile a qrpm.yml hash and render the SPEC file
  # +dict+ is the compiler dictionary (command line overrides) and +target+
  # the build target
  def render(yaml, dict = {}, target = nil)
    yaml = { "name" => "pck", "version" => "1.0.0", "summary" => "summary" }.merge(yaml)
    Qrpm::Compiler.new(dict).compile(yaml).rpm(target: target).render
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

    it "emits one hard link ln line per reflink" do
      spec = render("$sbindir" => [
          { "reflink" => "/usr/bin/first" },
          { "reflink" => "/usr/bin/second" }
      ])
      expect(spec).to include "ln -f /usr/bin/first /usr/sbin/first"
      expect(spec).to include "ln -f /usr/bin/second /usr/sbin/second"
    end

    it "resolves rootbindir and rootsbindir on this system" do
      spec = render("$rootbindir" => ["bin/file"], "$rootsbindir" => ["sbin/file"])
      expect(spec).to include "\n#{Qrpm.resolve_dir("/bin")}/file\n"
      expect(spec).to include "\n#{Qrpm.resolve_dir("/sbin")}/file\n"
      expect(spec).not_to include "//"
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

    describe "target" do
      it "emits the macros of the target and tags the release" do
        spec = render({}, {}, "el7")
        expect(spec).to start_with "%global _binary_payload w9.gzdio\nName: pck\n"
        expect(spec).to include "Release: 1.el7\n"
      end
      it "emits nothing without a target" do
        spec = render({})
        expect(spec).to start_with "Name: pck\n"
        expect(spec).to include "Release: 1\n"
        expect(spec).not_to include "%global _binary_payload"
      end
      it "rejects unknown targets" do
        expect { render({}, {}, "el5") }.to raise_error(ArgumentError, /el5/)
      end
    end

    describe "config" do
      it "defaults to %config(noreplace) for files in /etc" do
        spec = render("$pcketcdir" => ["etc/file"], "/etc/cron.d" => ["etc/cron"])
        expect(spec).to include "%config(noreplace) /etc/pck/file\n"
        expect(spec).to include "%config(noreplace) /etc/cron.d/cron\n"
      end
      it "follows overridden configuration directories" do
        spec = render({ "$sysetcdir" => ["etc/a"], "$pcketcdir" => ["etc/b"] }, "sysetcdir" => "/opt/etc")
        expect(spec).to include "%config(noreplace) /opt/etc/a\n"
        expect(spec).to include "%config(noreplace) /opt/etc/pck/b\n"
      end
      it "has no default outside /etc" do
        spec = render("$bindir" => ["bin/file"], "/etcetera" => ["bin/file2"])
        expect(spec).not_to include "%config"
      end
      it "can be set explicitly" do
        spec = render("$bindir" => [{ "file" => "bin/a", "config" => true }, { "file" => "bin/b", "config" => "noreplace" }],
                      "$pcketcdir" => [{ "file" => "etc/c", "config" => false }])
        expect(spec).to include "%config /usr/bin/a\n"
        expect(spec).to include "%config(noreplace) /usr/bin/b\n"
        expect(spec).to include "\n/etc/pck/c\n"
      end
    end

    describe "owner" do
      it "emits %attr with user and group" do
        spec = render("$bindir" => [
            { "file" => "bin/a", "owner" => "apache.apache" },
            { "file" => "bin/b", "owner" => "apache" },
            { "file" => "bin/c", "owner" => ".apache", "perm" => "0640" }])
        expect(spec).to include "%attr(-,apache,apache) /usr/bin/a\n"
        expect(spec).to include "%attr(-,apache,-) /usr/bin/b\n"
        expect(spec).to include "%attr(0640,-,apache) /usr/bin/c\n"
      end
      it "combines with config" do
        spec = render("$pcketcdir" => [{ "file" => "etc/a", "owner" => "apache" }])
        expect(spec).to include "%config(noreplace) %attr(-,apache,-) /etc/pck/a\n"
      end
    end

    describe "directories" do
      it "creates an empty directory with owner and permissions" do
        spec = render("$vardir" => [{ "dir" => "store", "owner" => "apache.apache", "perm" => "0750" }])
        expect(spec).to include "mkdir -p %{buildroot}/var/lib %{buildroot}/var/lib/store\n"
        expect(spec).to include "%dir %attr(0750,apache,apache) /var/lib/store\n"
        expect(spec).not_to include "cp "
      end
      it "lets other entries add files to the directory" do
        spec = render("$pckvardir" => [{ "dir" => "store", "perm" => "0750" }], "$pckvardir/store" => ["var/file"])
        expect(spec).to include "%dir %attr(0750,-,-) /var/lib/pck/store\n"
        expect(spec).to include "\n/var/lib/pck/store/file\n"
        expect(spec[/^mkdir.*$/].scan("%{buildroot}/var/lib/pck/store").size).to eq 1
      end
      it "does not get a config default" do
        spec = render("$pcketcdir" => [{ "dir" => "conf.d" }])
        expect(spec).to include "%dir /etc/pck/conf.d\n"
        expect(spec).not_to include "%config"
      end
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

require 'tmpdir'
require 'fileutils'

describe "Qrpm" do
  def git(dir, *args)
    system("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", *args,
           out: File::NULL, err: File::NULL) or raise "git #{args.join(" ")} failed"
  end

  describe "::parse_version" do
    def version(name) Qrpm.parse_version(name)&.first end

    it "parses semantic versions" do
      expect(version("1.2.3")).to eq "1.2.3"
      expect(version("1.2")).to eq "1.2"
      expect(version("1.2.3.4")).to eq "1.2.3.4"
    end
    it "accepts a 'v' prefix" do
      expect(version("v1.2.3")).to eq "1.2.3"
      expect(version("V1.2.3")).to eq "1.2.3"
    end
    it "accepts a word prefix" do
      expect(version("release-1.2.3")).to eq "1.2.3"
      expect(version("release/1.2.3")).to eq "1.2.3"
      expect(version("rel_v1.2.3")).to eq "1.2.3"
    end
    it "separates pre-release suffixes with '~'" do
      expect(version("1.2.3-rc1")).to eq "1.2.3~rc1"
      expect(version("1.2.3.beta.2")).to eq "1.2.3~beta2"
      expect(version("1.2.3a")).to eq "1.2.3~a"
    end
    it "drops build metadata" do
      expect(version("1.2.3+build.5")).to eq "1.2.3"
    end
    it "rejects names that are not versions" do
      %w(main dev foo 1.2.x v1.2.3.tar.gz release).each { |name|
        expect(version(name)).to be_nil, "#{name} was accepted"
      }
    end
    it "orders pre-releases before the final version" do
      keys = %w(1.2.3-rc1 1.2.3 1.10.0 1.9.9).map { |n| Qrpm.parse_version(n) }
      expect(keys.max_by(&:last).first).to eq "1.10.0"
      expect(keys.first(2).max_by(&:last).first).to eq "1.2.3"
    end
  end

  describe "::resolve_dir" do
    it "resolves symbolic links" do
      Dir.mktmpdir { |dir|
        FileUtils.mkdir "#{dir}/target"
        File.symlink "target", "#{dir}/link"
        expect(Qrpm.resolve_dir("#{dir}/link")).to eq File.realpath("#{dir}/target")
      }
    end
    it "returns other paths unchanged" do
      Dir.mktmpdir { |dir|
        expect(Qrpm.resolve_dir(dir)).to eq dir
        expect(Qrpm.resolve_dir("#{dir}/missing")).to eq "#{dir}/missing"
      }
    end
  end

  describe "::chmod_to_octal" do
    def octal(mode) Qrpm.chmod_to_octal(mode) end

    it "translates absolute modes" do
      expect(octal("u=rwx,go=rx")).to eq "0755"
      expect(octal("u=rw,g=r,o=")).to eq "0640"
      expect(octal("a=r")).to eq "0444"
      expect(octal("=rwx")).to eq "0777"
    end
    it "translates '+' relative to an initial mode of 0" do
      expect(octal("u+rwx,go+rx")).to eq "0755"
      expect(octal("+x")).to eq "0111"
    end
    it "handles setuid, setgid, and sticky bits" do
      expect(octal("u+s,a=rx")).to eq "4555"
      expect(octal("g+s,a=rx")).to eq "2555"
      expect(octal("a=rwx,+t")).to eq "1777"
    end
    it "rejects '-' and 'X'" do
      expect { octal("a-x") }.to raise_error(ArgumentError)
      expect { octal("u=rwX") }.to raise_error(ArgumentError)
    end
  end

  describe "::file_version" do
    def scan(content)
      Dir.mktmpdir { |dir|
        File.write "#{dir}/file", content
        Qrpm.file_version("#{dir}/file")
      }
    end

    it "returns the version assigned to a version variable" do
      expect(scan("module X\n  VERSION = \"0.6.0\"\nend\n")).to eq "0.6.0"
      expect(scan("__version__ = '1.2.3-rc1'\n")).to eq "1.2.3~rc1"
      expect(scan("{ \"name\": \"x\", \"version\": \"2.0.0\" }\n")).to eq "2.0.0"
    end
    it "skips other dotted numbers before the version assignment" do
      expect(scan("[project]\nrequires-python = \">=3.8\"\nversion = \"2.1.0\"\n")).to eq "2.1.0"
      expect(scan("# Needs Python 3.8+\n__version__ = '1.0'\n")).to eq "1.0"
    end
    it "falls back to the first version in the file" do
      expect(scan("1.2.3\n")).to eq "1.2.3"
      expect(scan("v1.0 and later 2.0")).to eq "1.0"
    end
    it "ignores numbers without dots" do
      expect(scan("count = 42\nversion = 1.5\n")).to eq "1.5"
    end
    it "returns nil if there is no version" do
      expect(scan("no version here\n")).to be_nil
    end
  end

  describe "::git_version" do
    around(:each) do |example|
      Dir.mktmpdir { |dir|
        @repo = dir
        git(dir, "init", "-q", "-b", "main")
        example.run
      }
    end

    attr_reader :repo

    def commit(msg) git(repo, "commit", "-q", "--allow-empty", "-m", msg) end

    it "returns the highest version among the tags reachable from HEAD" do
      commit "first"
      git(repo, "tag", "v1.2.3")
      git(repo, "tag", "release-1.10.0")
      git(repo, "tag", "not-a-version")
      commit "second"
      git(repo, "tag", "v1.9.0")
      expect(Qrpm.git_version(repo)).to eq "1.10.0"
    end

    it "ignores tags that are not reachable from HEAD" do
      commit "first"
      git(repo, "tag", "v1.0.0")
      git(repo, "checkout", "-q", "-b", "other")
      commit "other"
      git(repo, "tag", "v9.0.0")
      git(repo, "checkout", "-q", "main")
      expect(Qrpm.git_version(repo)).to eq "1.0.0"
    end

    it "falls back to the name of the current branch" do
      commit "first"
      git(repo, "checkout", "-q", "-b", "release/2.1.0")
      expect(Qrpm.git_version(repo)).to eq "2.1.0"
    end

    it "prefers tags over the branch name" do
      commit "first"
      git(repo, "tag", "v1.0.0")
      git(repo, "checkout", "-q", "-b", "release/2.1.0")
      expect(Qrpm.git_version(repo)).to eq "1.0.0"
    end

    it "returns nil if no version is found" do
      commit "first"
      expect(Qrpm.git_version(repo)).to be_nil
    end

    it "returns nil in a repository without commits" do
      expect(Qrpm.git_version(repo)).to be_nil
    end

    it "returns nil outside a git repository" do
      Dir.mktmpdir { |dir| expect(Qrpm.git_version(dir)).to be_nil }
    end
  end

  describe "::dirty?" do
    around(:each) do |example|
      Dir.mktmpdir { |dir|
        @repo = dir
        git(dir, "init", "-q", "-b", "main")
        %w(a b).each { |sub|
          FileUtils.mkdir_p "#{dir}/#{sub}"
          File.write "#{dir}/#{sub}/file", "content\n"
        }
        git(dir, "add", ".")
        git(dir, "commit", "-q", "-m", "init")
        example.run
      }
    end

    attr_reader :repo

    it "is false in a clean repository" do
      expect(Qrpm.dirty?(repo)).to be false
      expect(Qrpm.dirty?("#{repo}/a")).to be false
    end

    it "is true when a tracked file below the directory is modified" do
      File.write "#{repo}/a/file", "changed\n"
      expect(Qrpm.dirty?("#{repo}/a")).to be true
      expect(Qrpm.dirty?(repo)).to be true
    end

    it "ignores changes elsewhere in the repository" do
      File.write "#{repo}/b/file", "changed\n"
      expect(Qrpm.dirty?("#{repo}/a")).to be false
    end

    it "ignores untracked files" do
      File.write "#{repo}/a/untracked", "new\n"
      expect(Qrpm.dirty?("#{repo}/a")).to be false
    end

    it "is false outside a git repository" do
      Dir.mktmpdir { |dir| expect(Qrpm.dirty?(dir)).to be false }
    end
  end
end

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

  describe "::file_version" do
    def scan(content)
      Dir.mktmpdir { |dir|
        File.write "#{dir}/file", content
        Qrpm.file_version("#{dir}/file")
      }
    end

    it "returns the first version in the file" do
      expect(scan("module X\n  VERSION = \"0.6.0\"\nend\n")).to eq "0.6.0"
      expect(scan("__version__ = '1.2.3-rc1'\n")).to eq "1.2.3~rc1"
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

require 'tmpdir'
require 'fileutils'

describe "Qrpm" do
  describe "::dirty?" do
    def git(dir, *args)
      system("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", *args,
             out: File::NULL, err: File::NULL) or raise "git #{args.join(" ")} failed"
    end

    around(:each) do |example|
      Dir.mktmpdir { |dir|
        @repo = dir
        git(dir, "init", "-q")
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

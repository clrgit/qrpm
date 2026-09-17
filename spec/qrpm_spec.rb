require 'tmpdir'
require 'fileutils'

describe "qrpm" do
  it 'has a version number' do
    expect(Qrpm::VERSION).not_to be_nil
  end

  describe "Qrpm#evaluate" do
    def git(dir, *args)
      system("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", *args,
             out: File::NULL, err: File::NULL) or raise "git #{args.join(" ")} failed"
    end

    # Compile a qrpm file with +srcdir+ as source directory and return the
    # evaluated Qrpm object
    def evaluate(srcdir, yaml = {})
      yaml = { "name" => "pck", "summary" => "summary", "srcdir" => srcdir }.merge(yaml)
      Qrpm::Compiler.new({}).compile(yaml).evaluate
    end

    it "uses the highest git tag as the default version" do
      Dir.mktmpdir { |dir|
        git(dir, "init", "-q")
        git(dir, "commit", "-q", "--allow-empty", "-m", "init")
        git(dir, "tag", "v1.2.3")
        git(dir, "tag", "v1.10.0")
        expect(evaluate(dir)["version"]).to eq "1.10.0"
      }
    end

    it "uses the branch name as the default version if there are no tags" do
      Dir.mktmpdir { |dir|
        git(dir, "init", "-q", "-b", "release/2.0.0")
        git(dir, "commit", "-q", "--allow-empty", "-m", "init")
        expect(evaluate(dir)["version"]).to eq "2.0.0"
      }
    end

    it "reads the version from version_file" do
      Dir.mktmpdir { |dir|
        FileUtils.mkdir_p "#{dir}/lib"
        File.write "#{dir}/lib/version.rb", "VERSION = \"4.5.6\"\n"
        expect(evaluate(dir, "version_file" => "lib/version.rb")["version"]).to eq "4.5.6"
      }
    end

    it "fails if version_file has no version" do
      Dir.mktmpdir { |dir|
        File.write "#{dir}/VERSION", "none\n"
        expect { evaluate(dir, "version_file" => "VERSION") }.to raise_error(Qrpm::Error, /Can't find a version in 'VERSION'/)
      }
    end

    it "fails if version_file doesn't exist" do
      Dir.mktmpdir { |dir|
        expect { evaluate(dir, "version_file" => "VERSION") }.to raise_error(Qrpm::Error, /Can't find version file 'VERSION'/)
      }
    end

    it "fails if both version and version_file are given" do
      Dir.mktmpdir { |dir|
        expect { evaluate(dir, "version" => "1.0", "version_file" => "VERSION") }.to raise_error(Qrpm::CompileError, /both/)
      }
    end

    it "applies the default to a version with a null value" do
      Dir.mktmpdir { |dir|
        git(dir, "init", "-q")
        git(dir, "commit", "-q", "--allow-empty", "-m", "init")
        git(dir, "tag", "v7.0.0")
        expect(evaluate(dir, "version" => nil)["version"]).to eq "7.0.0"
      }
    end

    it "uses an explicit version" do
      Dir.mktmpdir { |dir|
        expect(evaluate(dir, "version" => "2.0.0")["version"]).to eq "2.0.0"
      }
    end

    it "fails if the git repository has no version tag or branch" do
      Dir.mktmpdir { |dir|
        git(dir, "init", "-q", "-b", "main")
        expect { evaluate(dir) }.to raise_error(Qrpm::Error, /Add a 'version' field/)
      }
    end

    it "fails if the source directory is not in a git repository" do
      Dir.mktmpdir { |dir|
        expect { evaluate(dir) }.to raise_error(Qrpm::Error, /Add a 'version' field/)
      }
    end

    it "fails if a mandatory field is empty" do
      Dir.mktmpdir { |dir|
        expect { evaluate(dir, "version" => "1.0", "summary" => "") }.to raise_error(Qrpm::Error, /'summary'/)
      }
    end
  end
end

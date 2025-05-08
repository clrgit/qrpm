require 'erb'
require 'fileutils'

module Qrpm
  # Knows the following RPM fields:
  #
  #   name        Package name (mandatory)
  #   version     Version (mandatory)
  #   release     Release
  #   summary     Short one-line description of package (mandatory)
  #   description Description
  #   packager    Name of the packager (defaults to the name of the user or
  #               $USER@$HOSTNAME if not found)
  #   license     License (defaults to GPL)
  #   require     Array of required packages
  #   make        Controls the build process:
  #                 true    Expect the top-level directory to contain
  #                         configure or make files and runs them. It is an
  #                         error if the Makefile is missing
  #                 (possibly multiline command)
  #                         Runs the command to build the project
  #
  # Each field has a dynamically generated accessor method that can be
  # referenced in the template file
  class Rpm
    MANDATORY_FIELDS = %w(name version summary)

    # Maps from field name to array of allowed types for that field
    FIELDS = MANDATORY_FIELDS.map { |f| [f, [String]] }.to_h.merge({
      "release" => [String],
      "description" => [String],
      "packager" => [String],
      "license" => [String],
      "group" => [String],
      "include" => [Array, String],
      "require" => [Array, String],
      "make" => [String]
    })

    RPM_DIRS = %w(SOURCES BUILD RPMS SPECS SRPMS tmp)

    # Field accessor methods. FIXME Value should have been resolved
    FIELDS.each { |f,ts|
      if ts.include? Array
        eval <<-EOS
          def #{f}()
            case v = @fields["#{f}"]
              when ValueNode
                v.value
              when ArrayNode
                v.values.map(&:value)
              when NilClass
                nil
              else
                raise ArgumentError, "Can this even happen?"
            end
          end
        EOS
      else
        eval "def #{f}() @fields[\"#{f}\"]&.value end"
      end
    }

    attr_reader :fields
    attr_reader :nodes

    # The source directory
    attr_reader :srcdir

    # The content of the SPEC file
    attr_reader :spec

    def files() @files ||= nodes.select(&:file?) end
    def links() @links ||= nodes.select(&:link?) end
    def reflinks() @reflinks ||= nodes.select(&:reflink?) end
    def symlinks() @symlinks ||= nodes.select(&:symlink?) end

    def initialize(srcdir, fields, nodes, template: QRPM_ERB_FILE)
      constrain srcdir, String
      constrain fields, { String => Node }
      constrain nodes, [FileNode]
      @fields, @nodes = fields, nodes
      @srcdir = srcdir
      @template = template
    end

    def has_configure?() ::File.exist? "#{srcdir}/configure" end
    def has_make?() ::File.exist? "#{srcdir}/Makefile" end

    def build(target: :rpm, file: nil, verbose: false, destdir: ".", builddir: nil)
      verb = verbose ? "" : "&>/dev/null"
      begin
        if builddir
          rootdir = builddir
          FileUtils.rm_rf(rootdir)
          FileUtils.mkdir_p(rootdir)
        else
          rootdir = Dir.mktmpdir
        end

        spec_file = file || "#{name}.spec"
        tar_file = "#{name}.tar.gz"
        spec_path = "#{rootdir}/SPECS/#{spec_file}"
        tar_path = "#{rootdir}/SOURCES/#{tar_file}"

        # Create directories
        RPM_DIRS.each { |dir| FileUtils.mkdir_p "#{rootdir}/#{dir}" }

        # Roll tarball
        #
        # It is a bad idea to use git-archive to roll a tarball because we may
        # have configuration files/scripts that are not included in the git
        # repository. If needed then see
        # https://gist.github.com/arteymix/03702e3eb05c2c161a86b49d4626d21f
        #
        # Alternatively use the --add-file option? Then we need to know if
        # files are in the git repo or not
        system "tar zcf #{tar_path} --transform=s%^\./%#{name}/% ." # FIXME FIXME

        # Create spec file. Initial blanks are removed from each line in the file
        renderer = ERB.new(IO.read(@template).sub(/^__END__\n.*/m, ""), trim_mode: "-")
        @spec = renderer.result(binding).gsub(/^[[:blank:]]*/, "")

        # Emit spec or build RPM
        if target == :spec
          destfiles = ["#{destdir}/#{spec_file}"]
          IO.write(destfiles.first, @spec)
        else
          IO.write(spec_path, @spec)
          rpm_build_options = [
              "-v -ba",
              "-D 'debug_package %{nil}'",
              "--define \"_topdir #{rootdir}\"",
          ].join(" ")
          system "rpmbuild #{rpm_build_options} #{rootdir}/SPECS/#{name}.spec #{verb}" or
              raise "Failed building RPM file. Re-run with -v option to see errors"
          if target == :srpm
            destfiles = Dir["#{rootdir}/SRPMS/*"]
            !destfiles.empty? or raise Error, "No SRPM file found"
          elsif target == :rpm
            destfiles = Dir["#{rootdir}/RPMS/*/#{name}-[0-9]*"]
            !destfiles.empty? or raise Error, "No RPM file found"
          else
            raise ArgumentError, "Not a valid value for :target - #{target.inspect}"
          end
          system "cp #{destfiles.join " "} #{destdir}" or raise "Failed copying SRPM file"
        end
        return destfiles
      ensure
        FileUtils.remove_entry_secure rootdir if !builddir
      end
    end

    def dump
      puts self.class
      indent {
        puts "fields"
        indent { fields.sort_by(&:first).each { |k,v| puts "#{k}: #{v.value}" } }
        puts "nodes"
        indent { nodes.map(&:dump) }
      }
    end
  end
end


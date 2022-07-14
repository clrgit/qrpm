require 'erb'
require 'fileutils'

module Qrpm
  class Rpm
    # Defines the following member methods:
    #
    #   name        Package name (mandatory)
    #   version     Version (mandatory)
    #   release     Release
    #   license     License (defaults to GPL)
    #   summary     Short one-line description of package (mandatory)
    #   description Description
    #   packager    Name of the packager (defaults to the name of the user or 
    #               $USER@$HOSTNAME if not found)
    #   require     Array of required packages
    #   make        Controls the build process:
    #                 null    Search the top-level directory for configure or
    #                         make files and runs them. Skip building if not 
    #                         found. This is the default
    #                 true    Expect the top-level directory to contain 
    #                         configure make files and runs them. It is an 
    #                         error if the Makefile is missing
    #                 (array of commands)
    #                         Runs the commands to build the project
    #
    FIELDS = %w(name version release group license summary description packager requires make)
    MANDATORY_FIELDS = %w(name summary version)

    TEMPLATE = "#{::File.dirname(__FILE__)}/template.erb"
    RPM_DIRS = %w(SOURCES BUILD RPMS SPECS SRPMS tmp)

    # Field accessor methods
    FIELDS.each { |f| eval "def #{f}() @fields[\"#{f}\"] end" }

    attr_reader :fields
    attr_reader :nodes

    # The content of the SPEC file
    attr_reader :spec

    def files() @files ||= nodes.select(&:file?) end
    def links() @lines ||= nodes.select(&:link?) end

    def verbose?() @verbose end

    def initialize(fields, nodes, template: TEMPLATE, verbose: false)
      @fields, @nodes = fields, nodes
      @template = template
      @verbose = verbose
      @verb = verbose ? "" : "&>/dev/null"
    end

    def has_configure?() ::File.exist? "configure" end
    def has_make?() ::File.exist? "make" end

    def build(target: :rpm, file: nil, verbose: false, destdir: ".")
      verb = verbose ? "" : "&>/dev/null"
      Dir.mktmpdir { |rootdir|
        FileUtils.rm_rf(rootdir)
        FileUtils.mkdir_p(rootdir)

        spec_file = file || "#{name}.spec"
        tar_file = "#{name}.tar.gz"
        spec_path = "#{rootdir}/SPECS/#{spec_file}"
        tar_path = "#{rootdir}/SOURCES/#{tar_file}"

        # Create directories
        RPM_DIRS.each { |dir| FileUtils.mkdir_p "#{rootdir}/#{dir}" }

        # Roll tarball
        #
        # It is a bad idea to use git-archive to roll a tarball because we may have 
        # configuration files/scripts that are not included in the git repository. If
        # needed then see https://gist.github.com/arteymix/03702e3eb05c2c161a86b49d4626d21f
        system "tar zcf #{tar_path} --transform=s%^\./%#{name}/% ."

        # Create spec file
        renderer = ERB.new(IO.read(@template).sub(/^__END__\n.*/m, ""), trim_mode: "-")
        @spec = renderer.result(binding)

        # Emit spec or build RPM
        if target == :spec
          IO.write("#{destdir}/#{spec_file}", @spec)
        else
          IO.write(spec_path, @spec)
          system "rpmbuild -v -ba --define \"_topdir #{rootdir}\" #{rootdir}/SPECS/#{name}.spec #{verb}" or
              raise "Failed building RPM file. Re-run with -v option to see errors"
          if target == :srpm
            system "cp #{rootdir}/SRPMS/* #{destdir}" or raise "Failed copying SRPM file"
          elsif target == :rpm
            system "cp #{rootdir}/RPMS/*/#{name}-[0-9]* #{destdir}" or raise "Failed copying RPM file"
          else
            raise ArgumentError, "Not a valid value for :target - #{target.inspect}"
          end
        end
      }
    end

    def dump
      puts self.class
      indent {
        puts "fields"
        indent { fields.each { |k,v| puts "#{k}: #{v.inspect}" } }
        puts "nodes"
        indent { nodes.map(&:dump) }
      }
    end
  end
end


require 'erb'
require 'fileutils'

module Qrpm
  class Rpm
    # Defines the following member methods:
    #
    #   name        Package name
    #   version     Version
    #   release     Release
    #   license     License (defaults to GPL)
    #   summary     Short one-line description of package
    #   description Description
    #   packager    Name of the packager (defaults to the value of the $USER 
    #               environment variable)
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

    def has_configure?() ::File.exist? "configure" end
    def has_make?() ::File.exist? "make" end

    def initialize(fields, nodes, template: TEMPLATE)
      @fields, @nodes = fields, nodes
      @template = template
    end

    def build(target: :rpm, file: nil)
      Dir.mktmpdir { |rootdir|
        rootdir = "/home/clr/prj/qrpm/tmp"
        FileUtils.rm_rf(rootdir)
        FileUtils.mkdir_p(rootdir)

        spec_file = file || "#{name}.spec"
        tar_file = "#{name}.tar.gz"
        spec_path = "#{rootdir}/SPECS/#{spec_file}"
        tar_path = "#{rootdir}/SOURCES/#{tar_file}"

        # Create directories
        RPM_DIRS.each { |dir| FileUtils.mkdir_p "#{rootdir}/#{dir}" }

        # Directory for tarball creation. This lives inside the RPM directory
        # structure and is removed before we start rpmbuild
        tarroot = "#{rootdir}/tmp/#{name}"
        FileUtils.mkdir(tarroot)

        # Copy files
        FileUtils.cp_r(".", tarroot, preserve: true)
        
        # Roll tarball and put it in the SOURCES directory
        system "tar zcf #{tar_path} -C #{rootdir}/tmp #{name}" or raise "Can't roll tarball"

        # Remove temporary tar dir
        FileUtils.rm_rf tarroot

        # Create spec file
        renderer = ERB.new(IO.read(@template).sub(/^__END__\n.*/m, ""), trim_mode: "-")
        @spec = renderer.result(binding)

        # Emit spec or build RPM
        if target == :spec
          IO.write(spec_file, @spec)
        else
          IO.write(spec_path, @spec)
          system "rpmbuild -v -ba --define \"_topdir #{rootdir}\" #{rootdir}/SPECS/#{name}.spec" or
              raise "Failed building RPM file"
          if target == :srpm
            system "cp #{rootdir}/SRPMS/* ." or raise "Failed copying SRPM file"
          elsif target == :rpm
            system "cp #{rootdir}/RPMS/*/#{name}-[0-9]* ." or raise "Failed copying RPM file"
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


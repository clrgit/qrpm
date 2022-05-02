require 'erb'
require 'fileutils'

module Qrpm
  class Rpm
    FIELDS = %w(name version release group license summary description packager requires)
    MANDATORY_FIELDS = %w(name summary version)
    TEMPLATE = "#{::File.dirname(__FILE__)}/template.erb"

    RPM_DIRS = %w(SOURCES BUILD RPMS SPECS SRPMS tmp)

    # Field accessor methods
    FIELDS.each { |f| eval "def #{f}() @fields[\"#{f}\"] end" }

    attr_reader :fields
    attr_reader :nodes
    def files() @files ||= nodes.select(&:file?) end
    def links() @lines ||= nodes.select(&:link?) end

    def spec_file() end

    def initialize(fields, nodes, template: TEMPLATE)
      @fields, @nodes = fields, nodes
      @template = template
    end

    def build
      Dir.mktmpdir { |root|
        root = "tmp"
        FileUtils.rm_rf root
        FileUtils.mkdir root
        specfile = "#{root}/SPECS/#{name}.spec"
        tarfile = "#{root}/SOURCES/#{name}.tar.gz"
        tardir = ::File.basename(Dir.getwd)

        # Create directories
        RPM_DIRS.each { |dir| FileUtils.mkdir "#{root}/#{dir}" }

        # Create spec file
        renderer = ERB.new(IO.read(@template).sub(/^__END__\n.*/m, ""), trim_mode: "-")
        puts renderer.result(binding)
        IO.write(specfile, renderer.result(binding))

        # Compute tar files
        tar_files = files.map { |f| "#{tardir}/#{f.file}" }

        # Create source tarball
        system "cd ..; tar zcf #{tardir}/#{tarfile} #{tar_files.join(" ")}" or 
            ShellOpts::failure "Can't roll tarball"

        system "rpmbuild -v -bb --define \"_topdir #{Dir.getwd}/tmp\" tmp/SPECS/HEJ.spec"
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

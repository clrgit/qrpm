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
      tarfile = "#{name}.tar.gz"

      Dir.mktmpdir { |rootdir|
        rootdir = "tmp" # FIXME
        FileUtils.rm_rf rootdir # FIXME
        FileUtils.mkdir rootdir # FIXME

        specfile = "#{rootdir}/SPECS/#{name}.spec"
        tarfile = "#{rootdir}/SOURCES/#{name}.tar.gz"
        tmpdir = "#{rootdir}/tmp"

        # Create directories
        RPM_DIRS.each { |dir| FileUtils.mkdir "#{rootdir}/#{dir}" }

        # Directory for tarball creation
        tarroot = "#{tmpdir}/#{name}"
        FileUtils.mkdir(tarroot)

        # Copy files
        tar_files = files.map { |f| f.file }.join(" ")
        system "tar cf - #{tar_files} | tar xf - -C #{tarroot}"

        # Roll tarball
        system "tar zcf #{tarfile} -C #{tmpdir} #{name}" or raise "Can't roll tarball"

        # Remove temporary tar dir
        FileUtils.rm_rf tarroot

        # Create spec file
        renderer = ERB.new(IO.read(@template).sub(/^__END__\n.*/m, ""), trim_mode: "-")
        puts renderer.result(binding)

        IO.write(specfile, renderer.result(binding))

        system "rpmbuild -v -bb --define \"_topdir #{Dir.getwd}/tmp\" tmp/SPECS/#{name}.spec"
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


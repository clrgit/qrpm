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

    # The content of the SPEC file
    attr_reader :spec

    def files() @files ||= nodes.select(&:file?) end
    def links() @lines ||= nodes.select(&:link?) end

    def initialize(fields, nodes, template: TEMPLATE)
      @fields, @nodes = fields, nodes
      @template = template
    end

    def build(subject: all)
      Dir.mktmpdir { |rootdir|
        spec_file = "#{name}.spec"
        tar_file = "#{name}.tar.gz"
        spec_path = "#{rootdir}/SPECS/#{spec_file}"
        tar_path = "#{rootdir}/SOURCES/#{tar_file}"

        # Create directories
        RPM_DIRS.each { |dir| FileUtils.mkdir "#{rootdir}/#{dir}" }

        # Directory for tarball creation
        tarroot = "#{rootdir}/tmp/#{name}"
        FileUtils.mkdir(tarroot)

        # Copy files
        tar_files = files.map { |f| f.file }.join(" ")
        system "tar cf - #{tar_files} | tar xf - -C #{tarroot}"

        # Roll tarball
        system "tar zcf #{tar_path} -C #{rootdir}/tmp #{name}" or raise "Can't roll tarball"

        # Remove temporary tar dir
        FileUtils.rm_rf tarroot

        # Create spec file
        renderer = ERB.new(IO.read(@template).sub(/^__END__\n.*/m, ""), trim_mode: "-")
        @spec = renderer.result(binding)

        if subject == :spec
          IO.write(spec_file, @spec)
        else
          IO.write(spec_path, @spec)

          system "rpmbuild -v -bb --define \"_topdir #{rootdir}\" #{rootdir}/SPECS/#{name}.spec" or
              raise "Failed building RPM file"

          system "cp #{rootdir}/RPMS/*/#{name}-[0-9]* ." or
              raise "Failed copying .RPM file"
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


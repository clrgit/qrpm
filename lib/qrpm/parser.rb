
module Qrpm
  class Parser
    DICT_FIELDS = (Rpm::FIELDS - %w(requires)).map { |f| [f, true] }.to_h

    attr_reader :fields # Hash from field to value (which can be of any type)
    attr_reader :dirs # Hash from directory to list of entries
    attr_reader :files # List of files
    attr_reader :rpm # Resulting RPM object

    def initialize(fields)
      @fields = fields.dup
      @dirs = {}
      @files = []
    end

    def parse(yaml)
      # Collect .qrpm file variables and directories and the list of required
      # packages. Variables are merged into +fields+
      yaml.each { |k,v|
        if k =~ /[\/.]/ || DIRS.key?(k) || DIRS.key?(k.sub(/^pck/, ""))
          (dirs[k] ||= []).concat v
        elsif k =~ /^[\w_]+$/
          fields[k] = v if !fields.key?(k)
        else
          raise "Illegal key/value: #{k}: #{v}"
        end
      }

      # Check for mandatory variables
      Rpm::MANDATORY_FIELDS.each { |f|
        fields.key?(f) or raise "Missing mandatory variable: #{f}"
      }

      # Get full name of user
      fullname = Etc.getpwnam(ENV['USER'])&.gecos
      if fullname.nil? || fullname == ""
        fullname = ENV['USER']
      end

      # Defaults for description and packager fields
      fields["description"] ||= fields["summary"]
      fields["packager"] ||= fullname
      fields["release"] ||= "0"
      fields["license"] ||= "GPL"

      # Expand variables in fields. The expansion mechanism doesn't depend on the order
      # of the variables
      expand_fields

      # Expand variables in directory entries. The algorithm is simpler than in
      # #expand_fields because no further variable defitinitions can happend
      expand_dirs

      # Replace symbolic directory names
      @dirs = dirs.map { |dir, files|
        if DIRS.key?(dir) 
          dir = DIRS[dir]
        elsif dir =~ /^pck(.*)$/ && DIRS.key?($1)
          dir = "#{DIRS[$1]}/#{fields["name"]}"
        end
        [dir, files]
      }.to_h

      # Build files
      dirs.each { |dir, nodes|
        nodes.each { |node|
          case node
            when Hash
              node = node.dup
              if node.key?("file")
                name = node.delete("name")
                file = node.delete("file")
                perm = node.delete("perm")
                node.empty? or raise "Illegal keys for file in directory #{dir}: #{node.keys}"
                files << Qrpm::File.new(dir, name, file, perm)
              elsif node.key?("link")
                name = node.delete("name")
                link = node.delete("link")
                node.empty? or raise "Illegal keys for link in directory #{dir}: #{node.keys}"
                files << Qrpm::Link.new(dir, name, link)
              else
                raise "Need either a 'file' or 'link' field for directory #{dir}"
              end
            when String
              files << Qrpm::File.new(dir, nil, node, nil)
          else
            raise "Illegal value for directory #{dir}: #{node}"
          end
        }
      }

      @rpm = Rpm.new(fields, files)
    end

    def self.parse(dict, yaml)
      Parser.new(dict).parse(yaml)
    end

  private
    MANDATORY_FIELDS = %w(name summary version)

    DIRS = {
      "etcdir" => "/etc",
      "bindir" => "/usr/bin",
      "sbindir" => "/usr/sbin",
      "libdir" => "/usr/lib",
      "libexecdir" => "/usr/libexec",
      "sharedir" => "/usr/share",
      "vardir" => "/var/lib",
      "spooldir" => "/var/spool",
      "rundir" => "/var/run",
      "lockdir" => "/var/lock",
      "cachedir" => "/var/cache",
      "tmpdir" => "/tmp",
      "logdir" => "/var/log"
    }

    # Returns array of variables in the object. Variables can be either '$name' or
    # '${name}'. The variables are returned in left-to-right order
    #
    def collect_variables(object, include_keys: false)
      case object
        when Array; object.map { |obj| collect_variables(obj) }
        when Hash; object.map { |k,v| (include_keys ? collect_variables(k) : []) + collect_variables(v) }
        when String; object.scan(/\$([\w_]+)|\$\{([\w_]+)\}/)
        when Integer, Float, true, false, nil; []
      else
        raise "Illegal object: #{object}"
      end.flatten.compact.uniq
    end

    # Expand variables in the given string
    #
    # The method takes care to substite left-to-rigth to avoid a variable expansion
    # to infer with the name of an immediately preceding variable. Eg. $a$b; if $b
    # is resolved to 'c' then a search would otherwise be made for a variable named
    # '$ac' 
    #
    def expand_variables(object, include_key: false)
      case object
        when Array; object.map { |e| expand_variables(e) }
        when Hash; object.map { |k,v| [expand_variables(k), expand_variables(v)] }.to_h
        when String
          s = object.dup
          collect_variables(object).each { |k| s.sub!(/\$#{k}|\$\{#{k}\}/, fields[k].to_s) }
          s
        when Integer, Float, true, false, nil; object
      else
        raise "Illegal object: #{object}"
      end
    end

    # Expands fields (but not directories). The algorithm allows fields to be
    # defined in any order
    #
    def expand_fields
      variables = fields.map { |k,v| [k, collect_variables(v)] }.to_h
      variables.values.flatten.uniq.each { |var|
        fields[var].nil? || fields[var].is_a?(String) or "Can't use '#{var}' as variable"
      }

      @fields, unresolved = fields.partition { |k,v| variables[k].empty? }.map(&:to_h)
      changed = true
      while changed && !unresolved.empty?
        changed = false
        unresolved.delete_if { |k,v|
          if variables[k].all? { |var| fields.key? var }
            fields[k] = expand_variables(unresolved[k])
            changed = true
          end
        }
      end
      unresolved.empty? or raise "Unresolved variables: #{unresolved.join(", ")}"
    end

    def expand_dirs
      @dirs = expand_variables(dirs)
    end
  end
end



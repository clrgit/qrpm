require 'open3'

module Qrpm
  class Compiler
  end

  class Parser
    # DICT_FIELDS = (Rpm::FIELDS - %w(requires)).map { |f| [f, true] }.to_h

    # Variable definitions. Map from variable path value. Both key and
    # value can contain variables
    attr_reader :defs

    # Map from variable path to key expression
    attr_reader :keys

    # Map from variable path to value expression
    attr_reader :values

    # Map from path to list of variables it depends on. Paths with no
    # dependencies have an empty list as value
    attr_reader :deps

    # Variables. A subset of defs
    attr_reader :vars

    # Directories. A subset of defs
    attr_reader :dirs

    def initialize(dict = {}, system_dirs: true)
      constrain dict, Hash
      @defs = system_dirs ? @defs = SYSTEM_DIRS.merge(dict) : dict
      @keys = {} # Map from variable key to key fragments
      @values = {} # Map from variable key to value fragments
      @deps = {} # Redundant - can be computed from @keys and @values
      @vars = {}
      @dirs = {}
    end

    # #parse returns self to it can be chained with eg. #analyze
    def parse(conf)
      collect_variables(nil, conf, [])
      @vars, @dirs = @defs.partition { |k,v| k !~ /[\$\/]/ }.map(&:to_h)
      self
    end

    def analyze
      # Remove top-level node
      deps.delete(nil) 

      # Remove duplicate dependencies
      deps.transform_values! { |v| v.uniq }

      # Add variables with empty dependencies
      defs.keys.each { |k| deps[k] ||= [] }

      # Detect undefined variables
      (keys.values + values.values).map(&:variables).flatten.each { |var|
        defs.key?(var) or raise "Undefined variable '#{var}'"
      }
      self
    end

    def compile(conf)
      parse(conf)
      analyze
      Qrpm.new(defs, keys, values, deps, vars, dirs)
    end

    def dump
      puts "Defs"
      indent { defs.each { |k,v| puts "#{k}: #{v.inspect}" } }
      puts "Deps"
      indent { deps.each { |k,v| puts "#{k}: #{v.join(", ")}" } }
    end

  private
    def collect_variables(path, object, inherited_key_deps)
      case object
        when Integer, Float
          inherited_key_deps
        when String
          @defs[path] = object
          @values[path] = Fragment.parse(object)
          @deps[path] = @values[path].variables
        when Hash
          @deps[path] = object.map { |k,v|
            k = k.to_s
            prefix = [path, k].compact.join(".")
            @keys[path] = Fragment.parse(k)
            key_deps = @keys[path].variables
            collect_variables(prefix, v, key_deps + inherited_key_deps)
          }.flatten
        when Array
          @deps[path] = object.map.with_index { |elem,i|
            elem_path = [path, "[#{i}]"].compact.join
            collect_variables(elem_path, elem, inherited_key_deps)
          }.flatten
      else
        raise ArgumentError, "Expected String, Hash, or Array. Got #{object.class}"
      end
    end
  end
end

    # Return an array of prefix/expr/var tuples. The prefix is the
    # string leading up to the variable. $NAME, ${NAME}, and $(COMMAND)
    # interpolations are recognized
#   def parse_string(string)
#     string.scan(/(.*?)(\\*)(\$#{IDENT_RE}|\$\{#{IDENT_RE}\}|\$\(.+\)|$)/).map { 
#         |prefix, backslashes, expr|
#       str = prefix + '\\' * (backslashes.size / 2)
#       if backslashes.size % 2 == 0
#         if expr
#           if expr[1] == "("
#             # Scan for embedded interpolations
#           else
#             var = expr.sub(/^\W+(.*)\W/, '\1')
#         else
#         end
#       else
#         str += interpolation
#       end
#       [str, var]
#     }[0..-2] # Last element is always ["", ""] because we have $ inside the capture in the RE
#   end





#   def collect_qrpm_variables(s)
#     s.scan(/\$([\w_]+)|\$\{([\w_.\[\]]+)\}/).flatten.compact
#   end

#   s.scan(/(.*?)(\\*)(\$[\w_][\w\d_.]*|\$\{[\w_][\w\d_.]*}|$)/).each { |a|


#   def collect_shell_variables(s)
#     s.scan(/\$\{\{([\w_.\[\]]+)\}\}/).flatten.compact
#   end

#   # FIXME: Doesn't handle '\'
#   def collect_string_variables(s)
#     s =~ /^(.*?)(?:\$\((.*)\)(.*))?$/
#     prefix, command, suffix = $1, $2 || "", $3 || ""
#     collect_qrpm_variables(prefix) + 
#         collect_shell_variables(command) +  
#         collect_qrpm_variables(suffix)
#   end

__END__
      # check for mandatory fields
      rpm::mandatory_fields.each { |f|
        fields.key?(f) or raise "missing mandatory variable: #{f}"
      }

      # get full name of user
      fullname = etc.getpwnam(env['user'])&.gecos
      if fullname.nil? || fullname == ""
        fullname = "#{env['user']}@#{env['hostname']}"
      end

      # defaults for description and packager fields
      fields["description"] ||= fields["summary"]
      fields["packager"] ||= fullname
      fields["release"] ||= "0"
      fields["license"] ||= "gpl"

      # expand variables in fields. the expansion mechanism doesn't depend on
      # the order of the variables
      expand_fields

      # expand variables in keys
      expand_keys

      # expand variables in directory entries
      expand_dirs

      # todo: add srcdir to directory entries (if defined)
      #expand_srcdir

      # replace symbolic directory names
      @dirs = dirs.map { |dir, files|
        if dirs.key?(dir) 
          dir = dirs[dir]
        elsif dir =~ /^pck(.*)$/ && dirs.key?($1)
          dir = "#{dirs[$1]}/#{fields["name"]}"
        end
        [dir, files]
      }.to_h

      # build files
      dirs.each { |dir, nodes|
        nodes.each { |node|
          case node
            when hash
              node = node.dup
              if node.key?("file")
                name = node.delete("name")
                file = node.delete("file")
                perm = node.delete("perm")
                node.empty? or raise "illegal keys for file in directory #{dir}: #{node.keys}"
                files << qrpm::file.new(dir, name, file, perm)
              elsif node.key?("link")
                name = node.delete("name")
                link = node.delete("link")
                node.empty? or raise "illegal keys for link in directory #{dir}: #{node.keys}"
                files << qrpm::link.new(dir, name, link)
              else
                raise "need either a 'file' or 'link' field for directory #{dir}"
              end
            when string
              files << qrpm::file.new(dir, nil, node, nil)
          else
            raise "illegal value for directory #{dir}: #{node}"
          end
        }
      }

      @rpm = rpm.new(fields, files)
    end

    def self.parse(dict, yaml)
      Parser.new(dict).parse(yaml)
    end

    def something
      conf.each { |k,v|
        collect_variables_recursively(nil, k, v)
      }
    end


    # Variables work like shell variables and are exported into the environment
    # before $(...) constructs are executed. The parser is primed with
    # environment variables that are legal variable names in in qrpm. Variable
    # assignment from the command line are then merged in
    #
    def parse2(conf)
      # Definitions. Map from key to value. Keys may contain variables that
      # will be expanded later
      #
      # Variables are keys that match a QRPM identifier but they're not
      # special-cased because the parser ensures that only variables can be
      # referenced
      defs = {}

      # Map from key to a list of variables its value depends on
      deps = {}

      # Set of referenced variables. Used to check for missing definitions
      # faster than iterating #deps. NIX
      refs = {}

      # Prime with command line variable assignments
      dict.map { |k,v|
        defs[k] = v
        deps[k] = []
      }

      # Scan for variables
      conf.each { |k,v|
        variables = collect_variables2("", k)
        case v
          when String
            (deps[k] ||= []) << *collect_variables2("", v)
          when Hash
            
            collect_variables2(k, v)
            puts "Found Hash"
          when Array
            puts "Found Array"
        end

          
        
        
        + collect_variables2(v)
        defs[k] = v
        deps[k] = variables
        variables.each { |v| ref[v] = true }
      }



        deps[k] ||= []
        deps[k] += key_variables
        (deps[k] ||= []) << *collect_variables2(k)
        case v
          when String
            (deps[k] ||= []) << *collect_variables2(v)
          when Hash
            puts "Found Hash"
          when Array
            puts "Found Array"
        end
          
      }
      exit
    end






#     # Prime with environment variables
#     #   Only the key is registered. Environment variables can only be used in
#     #   with shell expansion but are recorded to be able to scan commands for
#     #   QRPM variables
      #
      # Merge-in dict
      #
      # Scan for definitions and usages
      #   * $(...) construct are not scanned
      #   * Definitions are key/value pairs that may use other variables
      #   * Only key/value pairs where the key is a value key name literal are
      #     variables so that 'dir/dir' and '$dir/dir' are not variables
      
      # Variable names match /^[a-z][a-z0-9_]*$/

#     # Set of environment variables that are also legal QRPM variable names.
#     # This is used to exclude environment variables when scanning for QRPM
#     # variables in '$(...) commands
#     env = {} # Maps from name to true/false

      # Map from variable name to a list of variables that its value depends
      # on. It is also used to check if a variable has already been seen
      deps = {}

      # Map form variable to variable value
      vars = {}

      # Load environment variables
      env = ENV.select { |k,v| k =~ /^[a-z][a-z0-9_]*$/ }.map { |k,_| [k, true ] }.to_h

      # Prime deps with command line variable assignments
      deps = dict.map { |k,_| [k, []] }.to_h

      exit


      deps = @fields.keys.map { |k| [k, [nil]]  }.to_h
      yaml.each { |k,v|
        case v
          when String
            !deps.key?(k) or raise "Redefinition of variable '#{k}'"
            (deps[k] ||= []) << collect_variables2(v)
          when Hash
            puts "Found Hash"
          when Array
            puts "Found Array"
        end
          
      }
      exit
    end

    # Returns array of variables in the object. Variables can be either '$name'
    # or '${name}'. Nested variables are referred to as '${name.subname}'. The
    # variables are returned in left-to-right order
    #
    def collect_variables2(object, include_keys: false)
      case object
        when Array; object.map { |obj| collect_variables(obj) }
        when Hash; object.map { |k,v| (include_keys ? collect_variables(k) : []) + collect_variables(v) }
        when String; object.scan(/@([\w_]+)|\@\{([\w_]+)\}/)
        when Integer, Float, true, false, nil; []
      else
        raise "Illegal object: #{object}"
      end.flatten.compact.uniq
    end
    def extract_variables(s)
    end


    def parse(yaml)
      # Collect .qrpm file variables and directories and the list of required
      # packages. Variables are merged into +fields+
      yaml.each { |k,v|
        # Do shell expansion first
        k,v = substitute_shell_commands(k), substitute_shell_commands(v)

        if k =~ /[\/.]/ || DIRS.key?(k) || DIRS.key?(k.sub(/^pck/, ""))
          (dirs[k] ||= []).concat v
        elsif k =~ /^[\w_]+$/
          fields[k] = v if !fields.key?(k)
        elsif k =~ /^\$/ # Key variable
          # Key will be replaced with its expansion later
          if v.is_a? Array
            (dirs[k] ||= []).concat v
          else
            fields[k] = v
          end
        else
          raise "Illegal key/value: #{k.inspect}: #{v.inspect}"
        end
      }

      # check for mandatory fields
      rpm::mandatory_fields.each { |f|
        fields.key?(f) or raise "missing mandatory variable: #{f}"
      }

      # get full name of user
      fullname = etc.getpwnam(env['user'])&.gecos
      if fullname.nil? || fullname == ""
        fullname = "#{env['user']}@#{env['hostname']}"
      end

      # defaults for description and packager fields
      fields["description"] ||= fields["summary"]
      fields["packager"] ||= fullname
      fields["release"] ||= "0"
      fields["license"] ||= "gpl"

      # expand variables in fields. the expansion mechanism doesn't depend on
      # the order of the variables
      expand_fields

      # expand variables in keys
      expand_keys

      # expand variables in directory entries
      expand_dirs

      # todo: add srcdir to directory entries (if defined)
      #expand_srcdir

      # replace symbolic directory names
      @dirs = dirs.map { |dir, files|
        if dirs.key?(dir) 
          dir = dirs[dir]
        elsif dir =~ /^pck(.*)$/ && dirs.key?($1)
          dir = "#{dirs[$1]}/#{fields["name"]}"
        end
        [dir, files]
      }.to_h

      # build files
      dirs.each { |dir, nodes|
        nodes.each { |node|
          case node
            when hash
              node = node.dup
              if node.key?("file")
                name = node.delete("name")
                file = node.delete("file")
                perm = node.delete("perm")
                node.empty? or raise "illegal keys for file in directory #{dir}: #{node.keys}"
                files << qrpm::file.new(dir, name, file, perm)
              elsif node.key?("link")
                name = node.delete("name")
                link = node.delete("link")
                node.empty? or raise "illegal keys for link in directory #{dir}: #{node.keys}"
                files << qrpm::link.new(dir, name, link)
              else
                raise "need either a 'file' or 'link' field for directory #{dir}"
              end
            when string
              files << qrpm::file.new(dir, nil, node, nil)
          else
            raise "illegal value for directory #{dir}: #{node}"
          end
        }
      }

      @rpm = rpm.new(fields, files)
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

    # Look for a '$(shell-command)' construct and replace it with the result of
    # running the command
    def substitute_shell_commands(s)
      if s.is_a?(String) && s =~ /(.*?)\$\((.*)\)(.*)/
        prefix, cmd, suffix = $1, $2, $3
        stdout, stderr, status = Open3.capture3(cmd)
        status == 0 or raise "Failed expanding '$(#{cmd})'\n#{stderr}"
        prefix + stdout.chomp + suffix
      else
        s
      end
    end

    # Expand variables in keys (this is useful when a target directory depends
    # on the content of a variable)
    def expand_keys
      @fields = @fields.map { |k,v|
        if k.is_a? String
          s = k.dup
          collect_variables(k).each { |k| s.sub!(/\$#{k}|\$\{#{k}\}/, fields[k].to_s) }
          [s, v]
        else
          [k, v]
        end
      }.to_h
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
            fields[k] = expand_variables(unresolved[k]) # <- HER FIXME FIXME FIXME
            changed = true
          end
        }
      end
      unresolved.empty? or raise "Unresolved variables: #{unresolved.join(", ")}"
    end

    def expand_dirs
      @dirs = expand_variables(dirs)
    end

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
  end
end



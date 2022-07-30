require 'open3'

module Qrpm
  # The main result data are #defs and #deps. #keys and #values are the parsed
  # result of the keys and values of #deps and is used to interpolate strings
  # when values of dependent variables are known
  #
  # #defs is also partitioned into QRPM variables and directories
  class Compiler
    # Root node
    attr_reader :ast # TODO: Rename AST

    # Variable definitions. Map from path to Node
    attr_reader :defs

    # Map from path to list of variables it depends on. Paths with no
    # dependencies have an empty list as value
    attr_reader :deps

    # Dictionary. The dictionary object are compiled into the AST before it is
    # evaluated so the dictionary elements can be refered to with the usual
    # $var notation. #dict is automatically augmented with the default system
    # directory definitions unless :system_dirs is false
    attr_reader :dict

    # Defaults. Map from key to source expression
    attr_reader :defaults

    # If :srcdir is true, a default $srcdir variable is prefixed to all local
    # paths. This is the default. +srcdir:false+ is only used when testing
    def initialize(dict, system_dirs: true, defaults: true, srcdir: true)
      constrain dict, Hash
      @ast = nil
      @defs = {}
      @deps = {}
      @dict = system_dirs ? INSTALL_DIRS.merge(dict) : dict
      @use_system_dirs = system_dirs
      @use_defaults = defaults
      @use_srcdir = srcdir
    end

    # Parse the YAML source to an AST of Node objects and assign it to #ast.
    # Returns the AST
    def parse(yaml)
      # Root node
      @ast = RootNode.new

      # Compile standard directories. Also enter them into @defs so that #analyze
      # can access them by name before @defs is built by #collect_variables
      STANDARD_DIRS.each { |name| @defs[name] = StandardDirNode.new(@ast, name) } if @use_system_dirs

      # Parse yaml node
      yaml.each { |key, value|
        builtin_array = FIELDS[key]&.include?(ArrayNode) || false
        case [key.to_s, value, builtin_array]
          in [/[\/\$]/, _, _]; parse_directory_node(@ast, key, value)
          in [/^#{PATH_RE}$/, String, true]; parse_node(@ast, key, [value])
          in [/^#{PATH_RE}$/, Array, false]; parse_directory_node(@ast, key, value)
          in [/^#{PATH_RE}$/, _, _]; parse_node(@ast, key, value)
        else
          error "Illegal key: #{key.inspect}"
        end
      }

      # Compile and add dictionary to the AST. This allows command line
      # assignments to override spec file values
      dict.each { |k,v| [k, ValueNode.new(ast, k.to_s, Fragment::Fragment.parse(v))] }

      # Add defaults
      DEFAULTS.each { |k,v|
        next if k == "srcdir" # Special handling of $srcdir below
        parse_node(@ast, k, v) if !@ast.key?(k)
      } if @use_defaults

      # Only add a default $srcdir node when :srcdir is true
      parse_node(@ast, "srcdir", DEFAULTS["srcdir"]) if @use_srcdir && !@ast.key?("srcdir")

      @ast
    end

    # Analyze and decorate the AST tree. Returns the AST
    #
    # The various +check_*+ arguments are only used while testing to allow
    # illegal but short expressions by suppressing specified checks in
    # #analyze. The default is to apply all checks
    def analyze(
        check_undefined: true, 
        check_mandatory: true, 
        check_field_types: true, 
        check_directory_types: true)

      # Set package/system directory of standard directories depending on the
      # number of files in the directory
      dirs = @ast.values.select { |n| n.is_a? DirectoryNode }
      freq = dirs.map { |d| (d.key_variables & STANDARD_DIRS) * dirs.size }.flatten.tally
      freq.each { |name, count|
        node = @defs[name]
        if count == 1
          node.setsys
        else
          node.setpck
        end
      }

      # Collect definitions and dependencies
      ast.values.each { |node| collect_variables(node) }

      # Detect undefined variables and references to hashes or arrays
      if check_undefined
        deps.each { |path, path_deps|
          path_deps.each { |dep|
            if !defs.key?(dep)
              error "Undefined variable '#{dep}' in definition of '#{path}'"
            elsif !defs[dep].is_a?(ValueNode)
              error "Can't reference non-variable '#{dep}' in definition of '#{path}'"
            end
          }
        }
      end

      # Check for mandatory variables
      if check_mandatory
        missing = MANDATORY_FIELDS.select { |f| @defs[f].to_s.empty? }
        missing.empty? or error "Missing mandatory fields '#{missing.join("', '")}'"
      end

      # Check types of built-in variables
      if check_field_types
        FIELDS.each { |f,ts|
          ast.key?(f) or next
          ts.any? { |t| ast[f].class <= t } or error "Illegal type of field '#{f}'"
        }
      end

      @ast
    end

    # Compile YAML into a Qrpm object
    def compile(yaml)
      parse(yaml)
      analyze
      Qrpm.new(defs, deps)
    end

    def dump
      puts "Defs"
      indent { defs.each { |k,v| puts "#{k}: #{v.signature}" if v.interpolated? }}
      puts "Deps"
      indent { deps.each { |k,v| puts "#{k}: #{v.join(", ")}" if !v.empty? } }
    end

  private
    # Shorthand
    def error(msg) 
      raise CompileError, msg, caller
    end
    
    def parse_file_node(parent, hash)
      hash = { "file" => hash } if hash.is_a?(String)

      # Check for unknown keys
      unknown_keys = hash.keys - FILE_KEYS
      unknown_keys.empty? or 
          error "Illegal file attribute(s): #{unknown_keys.join(", ")}"

      # Check that exactly one of "file", "symlink", or "reflink" is defined
      (hash.keys & %w(file symlink reflink)).size == 1 or 
          error "Exactly one of 'file', 'symlink', or 'reflink' should be defined"

      # Check that perm is not used together with symlink or reflink
      (hash.keys & %w(symlink reflink)).empty? || !hash.key?("perm") or
          error "Can't use 'perm' together with 'symlink' or 'reflink'"

      # Normalize perm (YAML parses a literal 0644 as the integer 420!)
      hash["perm"] = sprintf "%04o", hash["perm"] if hash["perm"].is_a?(Integer)

      # Update file with srcdir
      hash["file"] &&= "$srcdir/#{hash["file"]}" if @use_srcdir

      # Create file node and add members
      FileNode.make(parent, hash)
    end

    def parse_directory_node(parent, key, value)
      constrain parent, RootNode
      constrain key, String, Symbol
      constrain value, String, Array, Hash
      dir = DirectoryNode.new(parent, Fragment::Fragment.parse(key.to_s))
      case value
        when String, Hash; parse_file_node(dir, value)
        when Array; value.each { |elem| parse_file_node(dir, elem) }
      end
      dir
    end

    def parse_node(parent, key, value)
      constrain parent, HashNode, ArrayNode
      constrain key, String, Symbol
      constrain value, String, Integer, Float, Hash, Array, nil
      key = key.to_s
      case value
        when String, Integer, Float
          ValueNode.new(parent, key, Fragment::Fragment.parse(value))
        when Hash
          node = HashNode.new(parent, key)
          value.each { |key, value| parse_node(node, key, value) }
          node
        when Array
          node = ArrayNode.new(parent, key)
          value.each.with_index { |value, idx| parse_node(node, idx.to_s, value) }
          node
        when nil
          ValueNode.new(parent, key, nil)
      end
    end

    # Collect variables from keys and values and add them to @defs and @deps
    #
    # Values and array have dependencies on their own while HashNode does not
    # and just forwards to its members
    def collect_variables(node)
      case node
        when StandardDirNode
          # (standard dirs are already added to @defs)
          @deps[node.path] = node.variables
        when ValueNode
          @defs[node.path] = node
          @deps[node.path] = node.variables
        when ArrayNode
          @defs[node.path] = node
          @deps[node.path] = node.traverse.map(&:variables).flatten.uniq
        when HashNode
          node.values.map { |n| collect_variables(n) }.flatten
      end
    end
  end
end


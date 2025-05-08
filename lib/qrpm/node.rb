
module Qrpm
  class Node
    # Parent node
    attr_reader :parent

    # Path to node. This is a String expression that leads from the
    # root node down to the current node. The expression may only contain
    # variables if the node is a DirectoryNode but it can include integer
    # indexes
    attr_reader :path

    # Name of node within its parent. ArrayNode element objects (this include
    # files) has integer "names" and only DirectoryNode keys may contain
    # references. It is initialized with a String or an Integer except for
    # DirectoryNode objects that are initialized with a Fragment::Expression
    # (directory nodes is not part of the dictionary). When computing directory
    # paths, the source of the Fragment::Expression is used
    attr_reader :name

    # The value of this node. This can be a Fragment::Expression (ValueNode),
    # Hash, or Array object
    attr_reader :expr

    # Interpolated #name. Initialized by Compile#analyze. Default an alias for #name
    alias_method :key, :name

    # Interpolated #expr. Initialized by Compile#analyze. Default an alias for #expr
    alias_method :value, :expr

    def initialize(parent, name, expr)
      constrain parent, HashNode, ArrayNode, nil
      constrain name, Fragment::Fragment, String, Integer, nil
      constrain expr, Fragment::Fragment, Hash, Array
      @parent = parent
      @name = name
      @expr = expr
      @interpolated = false
      @parent&.send(:add_node, self)
      @path = Node.ref(@parent&.path, self.is_a?(DirectoryNode) ? @name.source : name) # FIXME
    end

    # Return list of variable names in #expr. Directory nodes may include
    # variables in the key so they include key variables too
    def variables = abstract_method

    # Interpolate variables in Node. Note that interpolation is not recursive
    # except for DirectoryNode objects that interpolates both key and elements.
    # #interpolate sets the interpolated flag and returns self
    def interpolate(dict)
      @interpolated = true
      self
    end

    # True if object has been interpolated
    def interpolated? = @interpolated

    # Name of class
    def class_name = self.class.to_s.sub(/.*::/, "")

    # Signature. Used in tests
    def signature(klass: self.class_name, key: self.name) = abstract_method

    def inspect = "#<#{self.class} #{path.inspect}>"
    def dump = abstract_method

    # Traverse node and its children recursively and execute block on each
    # node. The nodes are traversed in depth-first order. The optional
    # +klasses+ argument is a list of Class objects and the block is only
    # executed on matching nodes. The default is to execute the block on all
    # nodes. Returns an array of traversed nodes if no block is given
    def traverse(*klasses, &block)
      klasses = klasses.flatten
      if block_given?
        yield self if klasses.empty? || klasses.include?(self.class)
        traverse_recursively(&block)
      else
        l = klasses.empty? || klasses.include?(self.class) ? [self] : []
        traverse_recursively { |n| l << n }
        l
      end
    end

    def dot(expr)
      curr = self
      src = ".#{expr}" if expr[0] != "["
      while src =~ /^\.(#{IDENT_RE})|\[(\d+)\]/
        member, index = $1, $2
        src = $'
        if member
          curr.is_a?(HashNode) or raise ArgumentError, "#{member} is not a hash in '#{expr}'"
          curr.key?(member) or raise ArgumentError, "Unknown member '#{member}' in '#{expr}'"
          curr = curr[member]
        else
          curr.is_a?(ArrayNode) or raise ArgumentError, "#{curr.key_source} is not an array in '#{expr}'"
          curr.size > index.to_i or raise "Out of range index '#{index}' in '#{expr}'"
          curr = curr[index]
        end
      end
      src.empty? or raise ArgumentError, "Illegal expression: #{expr}"
      curr
    end

  protected
    def self.ref(parent_ref, element)
      if parent_ref
        parent_ref + (element.is_a?(Integer) ? "[#{element}]" : ".#{element}")
      else
        element
      end
    end

    def traverse_recursively(&block) = abstract_method
    def signature_content = abstract_method
  end

  class ValueNode < Node
    # Source code of expression
    def source() @expr.source end

    # Override Qrpm#value. Initially nil, initialized by #interpolate
    attr_reader :value

    def initialize(parent, name, expr)
      expr ||= Fragment::NilFragment.new
      constrain expr, Fragment::Fragment
      super
    end

    # Override Qrpm methods
    def variables() @variables ||= expr.variables end

    def interpolate(dict)
      @value ||= expr.interpolate(dict) # Allows StandardDirNode to do its own assignment
      super
    end

    def signature() "#{class_name}(#{name},#{expr.source})" end
    def dump() puts value ? value : source end

  protected
    def traverse_recursively(&block) [] end
  end

  # Pre-defined standard directory node. #setsys and #setpck is used to point
  # the value at either the corresponding system or package directory depending
  # on the number of files in that directory
  class StandardDirNode < ValueNode
    def initialize(parent, name)
      super parent, name, nil
    end

    def signature() "#{class_name}(#{name},#{value.inspect})" end

    def setsys() @expr = Fragment::Fragment.parse("$sys#{name}") end
    def setpck() @expr = Fragment::Fragment.parse("$pck#{name}") end
  end

  class ContainerNode < Node
    # Return list of Node objects in the container. Hash keys are not included
    def exprs = abstract_method

    forward_to :expr, :empty?, :size, :[], :[]=

    def variables() @variables ||= exprs.map(&:variables).flatten.uniq end

    # Can't be defined as an alias because #exprs is redefined in derived
    # classes, otherwise #values would refer to the derived version of #exprs
    def values() exprs end

    def signature = "#{self.class_name}(#{name},#{exprs.map { |v| v.signature }.join(",")})"

  protected
    def traverse_recursively(&block)
      values.map { |value| value.traverse(&block) }.flatten
    end

    def add_node(node) = abstract_method
  end

  # A HashNode has a hash as expr. It doesn't forward #interpolate to its
  # members (FileNode overrides that)
  #
  class HashNode < ContainerNode
    # Override ContainerNode#exprs
    def exprs() expr.values end

    def initialize(parent, name, hash = {})
      constrain hash, Hash
      super(parent, name, hash.dup)
    end

    forward_to :expr, :key?, :keys

    def dump
      puts "{"
      indent {
        expr.each { |k,v|
          print "#{k}: "
          v.dump
        }
      }
      puts "}"
    end

  protected
    # Override ContainerNode#add_node
    def add_node(node) self[node.name] = node end
  end

  class RootNode < HashNode
    def initialize() super(nil, nil, {}) end

    # Override Node#interpolate. Only interpolates contained DirectoryNode
    # objects (TODO doubtfull - this is a Qrpm-level problem not a Node problem)
    def interpolate(dict)
      exprs.each { |e| e.is_a?(DirectoryNode) and e.interpolate(dict) }
      super
    end

    def signature = "#{self.class_name}(#{values.map { |v| v.signature }.join(",")})"
  end

  # A file. Always an element of a DirectoryNode object
  #
  # A file is a hash with an integer key and with the following expressions as members:
  #
  #   file        Source file. The source file path is prefixed with $srcdir if
  #               defined. May be nil
  #   name        Basename of the destination file. This defaults to the
  #               basename of the source file/symlink/reflink. The full path of
  #               the destination file is computed by prefixing the path of the
  #               parent directory
  #   reflink     Path on the target filesystem to the source of the reflink
  #               (hard-link). May be nil
  #   symlink     Path on the target filesystem to the source of the symlink.
  #               May be nil
  #   perm        Permissions of the target file in chmod(1) octal or rwx
  #               notation. May be nil
  #
  # Exactly one of 'file', 'symlink', and 'reflink' must be defined. 'perm'
  # can't be used together with 'symlink' or 'reflink'
  #
  # When interpolated the following methods are defined on a FileNode:
  #
  #   srcpath     Path to source file
  #   dstpath     Path to destination file
  #   dstname     Basename of destination file
  #   reflink     Path to source link
  #   symlink     Path to source link
  #   perm        Permissions
  #
  class FileNode < HashNode
    # Source file. This is the relative path to the file in the build directory
    # except for link files. Link files have a path on the target filesystem as
    # path. It is the interpolated value of #expr["file/reflink/symlink"]
    attr_reader :srcpath

    # Destination file path
    attr_reader :dstpath

    # Destination file name
    attr_reader :dstname

    # Hard-link file
    attr_reader :reflink

    # Symbolic link file
    attr_reader :symlink

    # Permissions of destination file. Perm is always a string
    attr_reader :perm

    # Directory
    def directory = parent.directory

    # Query methods
    def file? = !link?
    def link? = symlink? || reflink?
    def reflink? = @expr.key?("reflink")
    def symlink? = @expr.key?("symlink")

    def initialize(parent, name)
      constrain parent, DirectoryNode
      constrain name, Integer
      super
    end

    def interpolate(dict)
      super
      exprs.each { |e| e.interpolate(dict) }
      @srcpath = value[%w(file symlink reflink).find { |k| expr.key?(k) }].value
      @dstname = value["name"]&.value || File.basename(srcpath)
      @dstpath = "#{parent.directory}/#{@dstname}"
      @reflink = value["reflink"]&.value
      @symlink = value["symlink"]&.value
      @perm = value["perm"]&.value
      self
    end

    # :call-seq:
    #   FileNode.make(directory_node, filename)
    #   FileNode.make(directory_node, hash)
    #
    # Shorthand for creating file object
    def self.make(parent, arg)
      file = FileNode.new(parent, parent.size)
      hash = arg.is_a?(String) ? { "file" => arg } : arg
      hash.each { |k,v| ValueNode.new(file, k.to_s, Fragment::Fragment.parse(v)) }
      file
    end

    # Signature. Used in tests
    def signature = "FileNode(#{name},#{expr["file"].source})"

    # Path to source file. Returns the QRPM source expression or the
    # interpolated result if the FileNode object has been interpolated. Used by
    # Qrpm#dump
    def src
      e = expr["file"] || expr["reflink"] || expr["symlink"]
      interpolated? ? e.value : e.source
    end

    # Name of destination. Returns the QRPM source expression or the
    # interpolated result if the FileNode object has been interpolated. Used by
    # Qrpm#dump
    def dst
      if expr["name"]
        interpolated? ? expr["name"].value : expr["name"].expr.source
      else
        File.basename(src)
      end
    end
  end

  class ArrayNode < ContainerNode
    # Override ContainerNode#exprs
    def exprs() expr end

    def initialize(parent, name, array = [])
      constrain array, Array
      super(parent, name, array.dup)
    end

    forward_to :expr, :first, :last

    # Array forwards #interpolate to its children
    def interpolate(dict)
      exprs.each { |e| e.interpolate(dict) }
      super
    end

    def dump
      puts "["
      indent {
        expr.each { |n|
          print "- "
          n.dump
        }
      }
      puts "]"
    end

  protected
    def add_node(node)
      node.instance_variable_set(:"@name", expr.size)
      expr << node
    end
  end

  class DirectoryNode < ArrayNode
    # Override Qrpm#key
    attr_reader :key

    # File system path to the directory. An alias for uuid/key
    def directory() key end

    def initialize(parent, name, array = [])
      constrain name, Fragment::Fragment
      super
    end

    def variables() (super + key_variables).uniq end
    def key_variables() @key_variables ||= name.variables end

    # A directory node also interpolates its key
    def interpolate(dict)
      # #key is used by the embedded files to compute their paths so it has be
      # interpolated before we interpolate the files through the +super+ method
      @key = name.interpolate(dict)
      super
    end
  end
end


module Qrpm
  class Qrpm
    # Definitions. Maps from path to Node object
    attr_reader :defs

    # Dependencies. Maps from variable name to list of variables it depends on
    attr_reader :deps

    # Variable definitions. This is ValueNode, HashNode, and ArrayNode objects in #defs
    attr_reader :vars

    # Directory definitions. This is the Directory nodes in #defs
    attr_reader :dirs

    # File definitions. This is the File nodes in #defs
    attr_reader :files

    # Dictionary. Maps from path to interpolated value. Only evaluated nodes
    # have entries in #dict
    attr_reader :dict

    # Source directory
    def srcdir() @dict["srcdir"] end

    def initialize(defs, deps)
      constrain defs, { String => Node }
      @defs, @deps = defs, deps
      @vars, @dirs, @files = {}, {}, {}
      @defs.values.map(&:traverse).flatten.each { |object|
        case object
          when FileNode; @files[object.path] = object
          when DirectoryNode; @dirs[object.path] = object
          else @vars[object.path] = object
        end
      }
      @dict = {}
      @evaluated = false
    end

    # True if object has been evaluated
    def evaluated? = @evaluated

    # Evaluate object. Returns self
    def evaluate
      @evaluated ||= begin
        unresolved = @defs.dup # Queue of unresolved definitions

        # Find objects. Built-in RPM fields and directories are evaluated recursively
        paths = FIELDS.keys.select { |k| @defs.key? k } + dirs.keys #+ DEFAULTS.keys

        # Find dependency order of objects
        ordered_deps = find_evaluation_order(paths)

        # Evaluate objects and remove them from the @unresolved queue
        ordered_deps.each { |path|
          node = @defs[path]
          node.interpolate(dict) if !node.interpolated? && !dict.key?(path)
          unresolved.delete(path)
          @dict[path] = node.value if !node.is_a?(DirectoryNode) && !node.is_a?(FileNode)
        }
        self
      end
    end

    # Evaluate and return Rpm object
    def rpm(**rpm_options)
      evaluate
      used_vars = dict.keys.map { |k| [k, @defs[k]] }.to_h
      Rpm.new(dict["srcdir"], used_vars, files.values, **rpm_options)
    end
      
    def [](name) @dict[name] end
    def key?(name) @dict.key? name end

    def inspect
      "#<#{self.class}>"
    end

    def dump
      FIELDS.keys.each { |f| 
        puts if f == "make"
        obj = self[f]
        if obj.is_a?(Array)
          puts "#{f.capitalize}:"
          self[f].each { |e| indent.puts "- #{e.value}" }
        else
          puts "#{f.capitalize}: #{self[f]}" if key? f 
        end
      }
      puts
      puts "Directories:"
      indent {
        dirs.values.each { |d|
          puts d.key
          indent {
            d.values.each { |f|
              if f.file? && File.basename(f.src) == f.dst
                print f.src
              else
                joiner = f.file? ? "->" : (f.reflink? ? "~>" : "~~>")
                print "#{f.src} #{joiner} #{f.dst}"
              end
              print ", perm: #{f.perm}" if f.perm
              puts
            }
          }
        }
      }
    end

    def dump_parts(parts = [:defs, :deps, :vars, :dirs, :files, :dict])
      parts = Array(parts)
      if parts.include? :defs
        puts "Defs"
        indent { defs.each { |k,v| puts "#{k}: #{v.value.inspect}" if v.value } }
      end
      if parts.include? :deps
        puts "Deps"
        indent { deps.each { |k,v| puts "#{k}: #{v.join(", ")}" if !v.empty? } }
      end
      if parts.include? :vars
        puts "Vars"
        indent { vars.each { |k,v| puts "#{k}: #{v.inspect}" if !v.value.nil? } }
      end
      if parts.include? :dict
        puts "Dict"
        indent { dict.each { |k,v| puts "#{k}: #{v.inspect}" } }
      end
      if parts.include? :dirs
        puts "Dirs"
        indent { dirs.each { |k,v| puts "#{k}: #{v.directory}" } }
      end
      if parts.include? :files
        puts "Files"
        indent { files.each { |k,v| puts "#{k}: #{v.srcpath}" } }
      end
    end

  private
    # Assumes all required variables have been defined
    def interpolate(node)
      constrain node, Node
      node.interpolate(defs)
    end

    def find_evaluation_order(paths)
      paths.map { |path|
        @deps[path].empty? ? [path] : find_evaluation_order_recusively([], path).flatten.reverse + [path]
      }.flatten.uniq
    end

    def find_evaluation_order_recusively(stack, object)
      if stack.include? object 
        cycle = stack.drop_while { |e| e != object } + [object]
        raise "Cyclic definition: #{cycle.join(' -> ')}"
      end
      @deps[object].map { |e|
        if @deps.key?(e)
          [e] + find_evaluation_order_recusively(stack + [object], e)
        else
          []
        end
      }
    end

    def find_dependencies_recusively(stack, object)
      if stack.include? object 
        cycle = stack.drop_while { |e| e != object } + [object]
        raise "Cyclic definition: #{cycle.join(' -> ')}"
      end
      @deps[object].map { |e|
        [e] + find_dependencies_recusively(stack + [object], e)
      }
    end

    def to_val(obj)
      case obj
        when HashNode
          obj.exprs.map { |node| [node.key, to_val(node)] }.to_h
        when ArrayNode
          obj.exprs.map { |node| to_val(node.value) }
        when ValueNode
          obj.value
        when String
          obj
      else
        raise StandardError.new "Unexpected object class: #{obj.class}"
      end
    end
  end
end


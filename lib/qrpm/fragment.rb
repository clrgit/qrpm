
# TODO: Create (and use) a Fragment.parse method

module Qrpm
  module Fragment
    # A part of a key or value in the QRPM configuration file
    class Fragment
      # Source string of fragment. The top-level expression fragment has
      # the whole string as its source
      attr_reader :source

      # List of embedded fragments
      attr_reader :fragments

      def initialize(source, fragments = [])
        @source = source 
        @fragments = Array(fragments)
      end

      # Return true if this is a NilFragment. False except for NilFragment objects
      def is_nil?() false end

      # List of variables in the fragment (incl. child fragments)
      def variables() fragments.map(&:variables).flatten.uniq end

      # Interpolates fragment using dict and returns the result as a String
      def interpolate(dict) source end

      # Emit source
      def to_s = source

      # String representation of fragment. Used for debug and test
      def signature()
        r = "#{self.class.to_s.sub(/^.*::/, "")}(#{identifier})"
        r += "{" + fragments.map { |f| f.signature }.join(", ") + "}" if !fragments.empty?
        r
      end

      # Parse a JSON value into an Expression source
      def Fragment.parse(value)
        constrain value, String, Integer, Float, true, false, nil
        node = value.nil? ? NilFragment.new : parse_string(value.to_s)
        Expression.new(value.to_s, node)
      end

    protected
      # Used by #signature to display an identifier for a node
      def identifier() source.inspect.gsub('"', "'") end


    private
      # Parse string and return an array of Fragment sources. The string is
      # scanned for $NAME, ${NAME}, $(COMMAND), and ${{NAME}} inside $(COMMAND)
      # interpolations
      #
      # The string is parsed into Fragments to be able to interpolate it
      # without re-parsing
      #
      # Variable names needs to be '{}'-quoted if they're followed by a letter
      # or digit but not '.'. This makes it possible to refer to nested
      # variables without quotes. Eg '/home/$pck.home/dir' will be parsed as
      # '/home/${pck.home}/dir'
      def Fragment.parse_string(string)
        res = []
        string.scan(/(.*?)(\\*)(\$#{PATH_RE}|\$\{#{PATH_RE}\}|\$\(.+\)|$)/)[0..-2].each { 
            |prefix, backslashes, expr|
          expr.delete_suffix(".")
          text = prefix + '\\' * (backslashes.size / 2)
          if expr != ""
            if backslashes.size % 2 == 0
              if expr[1] == "(" # $()
                var = CommandFragment.new(expr)
                var.fragments.concat parse_shell_string(var.command)
              else # $NAME or ${NAME}
                var = VariableFragment.new(expr)
              end
            else
              text += expr
            end
          end
          res << TextFragment.new(text) if text != ""
          res << var if var
        }
        res
      end

      # Parse shell command string and return an array of Node sources
      def Fragment.parse_shell_string(string)
        res = []
        string.scan(/(.*?)(\\*)(\$\{\{#{PATH_RE}\}\}|$)/).each { |prefix, backslashes, expr|
          text = prefix + backslashes
          if expr != ""
            if backslashes.size % 2 == 0
              var = CommandVariableFragment.new(expr)
            else
              text += expr
            end
          end
          res << TextFragment.new(text) if text != ""
          res << var if var
        }
        res
      end
    end

    # Text without variables
    class TextFragment < Fragment
    end

    # Nil value
    class NilFragment < Fragment
      def is_nil?() true end
      def initialize() super(nil) end
    end

    # $NAME or ${NAME}
    class VariableFragment < Fragment
      # Name of the variable excluding '$' and '${}'
      attr_reader :name

      def initialize(source)
        super
        @name = source.sub(/^\W+(.*?)\W*$/, '\1')
      end

      def variables() [name] end
      def interpolate(dict) dict[name] end

    protected
      def identifier() name end
    end

    # ${{NAME}} in $(COMMAND) interpolations
    class CommandVariableFragment < VariableFragment
      def interpolate(dict) dict[name] end # FIXME: Proper shell escape
    end

    # Common code for CommandFragment and Expression
    class FragmentContainer < Fragment
      def interpolate(dict) fragments.map { |f| f.interpolate(dict) }.flatten.join end
    end

    # $(COMMAND)
    class CommandFragment < FragmentContainer
      # Command line excl. '$()'
      attr_reader :command

      def initialize(string)
        super(string)
        @command = string[2..-2]
      end

      def interpolate(dict)
        cmd = "set -eo pipefail; #{super}"
        stdout, stderr, status = Open3.capture3(cmd)
        status == 0 or raise Error.new "Failed expanding '$(#{cmd})'\n#{stderr}"
        stdout.chomp
      end
    end

    # A key or value as a list of Fragments
    class Expression < FragmentContainer
      def initialize(...)
        super
        @seen = {}
      end

      def interpolate(...)
        r = super
        !@seen.key?(r.inspect) or raise CompileError.new "Duplicate interpolation: #{r.inspect}"
        @seen[r.inspect] = true
        r
      end
    end
  end
end


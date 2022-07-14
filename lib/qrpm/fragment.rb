module Qrpm
  # A part of a key or value in the QRPM configuration file
  class Fragment
    # String of fragment. For variables this includes the '$', '${}', '$()',
    # '${{}}'. The top-level expression fragment has the whole string as its
    # literal
    attr_reader :litt

    # List of embedded fragments
    attr_reader :fragments

    def initialize(litt, fragments = [])
      @litt = litt 
      @fragments = fragments
    end

    # List of variables in the fragment (incl. child fragments)
    def variables() fragments.map(&:variables).flatten end

    # Interpolates fragment using dict
    def interpolate(dict) litt end

    # Parse a string into an Expression object
    def Fragment.parse(string)
      Expression.new(string, parse_string(string))
    end

  private
    IDENT_RE = /(?:[\w_][\w\d_.]*)/

    # Parse string and return an array of Fragment objects. The string is
    # scanned for $NAME, ${NAME}, $(COMMAND), and ${{NAME}} inside $(COMMAND)
    # interpolations
    #
    # The string is parsed into Fragment objects to be able to interpolate it
    # without re-parsing
    def Fragment.parse_string(string)
      res = []
      string.scan(/(.*?)(\\*)(\$#{IDENT_RE}|\$\{#{IDENT_RE}\}|\$\(.+\)|$)/)[0..-2].each { 
          |prefix, backslashes, expr|
        text = prefix + '\\' * (backslashes.size / 2)
        if expr != ""
          if backslashes.size % 2 == 0
            if expr[1] == "(" # $()
              var = CommandFragment.new(expr)
              var.fragments.concat parse_shell_string(var.command)
            else # $NAME or ${NAME}
              var = VarFragment.new(expr)
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

    # Parse shell command string and return an array of Node objects
    def Fragment.parse_shell_string(string)
      res = []
      string.scan(/(.*?)(\\*)(\$\{\{#{IDENT_RE}\}\}|$)/).each { |prefix, backslashes, expr|
        text = prefix + backslashes
        if expr != ""
          if backslashes.size % 2 == 0
            var = CommandVarFragment.new(expr)
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

  class TextFragment < Fragment
    # Add some text
    def concat(s) litt.concat s end
  end

  # $NAME or ${NAME}
  class VarFragment < Fragment
    # Name of the variable excluding '$' and '${}'
    attr_reader :name

    def initialize(litt)
      super
      @name = litt.sub(/^\W+(.*?)\W*$/, '\1')
    end

    def variables() [name] end
    def interpolate(dict) dict[name] end
  end

  # ${{NAME}} in $(COMMAND) interpolations
  class CommandVarFragment < VarFragment
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

    def initialize(litt)
      super(litt)
      @command = litt[2..-2]
    end

    def interpolate(dict) "$(" + super + ")" end
  end

  # A key or value as a list of Fragments
  class Expression < FragmentContainer
    alias_method :source, :litt
  end
end


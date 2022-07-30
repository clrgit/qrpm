#!/usr/bin/env ruby

require 'yaml'

p YAML.load(IO.read("t.yml"))

exit





require 'indented_io'

s = "member"

s =~ /^(\w+)|\[(\d+)\](?:\.|$)/
p $1
p $2


__END__

a = "1. $a 2. \\$a 3. \\\\$a 4. \\\\\\$a 5. \\\\\\\\$a rest"
b = "1. ${a} 2. \\${a} 3. \\\\${a} 4. \\\\\\${a} 5. \\\\\\\\${a} rest"
c = "1. $(a)"
d = "1. $a $(b $b ${b} ${{b}}) $c \\"

IDENT_RE = /(?:[\w_][\w\d_.]*)/

# Return an array of prefix/interpolated-variable tuples. The prefix is the
# string leading up to the variable. $NAME, ${NAME}, and $(COMMAND)
# interpolations are recognized
def parse_string(path, string)
  r = string.scan(/(.*?)(\\*)(\$#{IDENT_RE}|\$\{#{IDENT_RE}\}|\$\(.+\)|$)/).map { 
      |prefix, backslashes, interpolation|
    p [prefix, backslashes, interpolation]


    str = prefix + '\\' * (backslashes.size / 2)
    if backslashes.size % 2 == 0
      var = interpolation
    else
      str += '\\' * (backslashes.size % 2) + interpolation
    end
    [str, var]
  }[0..-2]
  puts
  r
end

#parse_string("a", a).each { |e| p e }
#exit

for s in [a, b, c, d] 
  puts "\"#{s}\""
  indent {
    parse_string("fake", s).each { |a|
      p a
    }
  }
  puts
end

#p a.scan(/\S+\s\S+/)


exit


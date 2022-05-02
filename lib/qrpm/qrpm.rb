
__END__
# Returns array of variables in the string. Variables can be either '$name' or
# '${name}'. The variables are returned in left-to-right order
#
def collect_exprs(expr)
  expr.scan(/\$([\w_]+)|\$\{([\w_]+)\}/).flatten.compact
end

# Expand variables in the given string
#
# The method takes case to substite left-to-rigth to avoid a variable expansion
# to infer with the name of an immediately preceding variable. Eg. $a$b; if $b
# is resolved to 'c' then a search would otherwise be made for a variable named
# '$ac' 
#
def expand_expr(dict, value)
  value = value.dup
  collect_exprs(value).each { |k| value.sub!(/\$#{k}|\$\{#{k}\}/, dict[k]) }
  value
end

def expand_dict(dict)
  expressions = dict.map { |k,v| [k, collect_exprs(v)] }.to_h
  result = expressions.select { |k, v| v.empty? }.map { |k,v| [k, dict[k]] }.to_h
  unresolved = dict.keys - result.keys

  changed = true
  while changed && !unresolved.empty?
    changed = false
    unresolved.delete_if { |k|
      if expressions[k].all? { |var| result.key? var }
        result[k] = expand_expr(result, dict[k])
        changed = true
      end
    }
  end
  unresolved.empty? or raise "Unresolved variables: #{unresolved.join(", ")}"

  result
end

# +value+ will typically be a dirs hash
def expand_object(dict, object)
  case object
    when Array; object.map { |v| expand_object(dict, v) }
    when Hash
      object.map { |k,v|
        key = expand_expr(dict, k)
        object = expand_object(dict, v)
        [key, object]
      }.to_h
    when String
      expand_expr(dict, object)
  else
    object
  end
end

def expand_dirs(dict, dirs)
  expand_object(dict, dirs)
end


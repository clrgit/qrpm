
module Qrpm
  class Lexer
    attr_reader :reldirs
    attr_reader :absdirs

    def initialize(reldirs, absdirs)
      @reldirs = reldirs.map { |p| File.expand_path(p) }
      @absdirs = absdirs.map { |p| File.expand_path(p) }
    end

    def self.load_yaml(file) # Is actually a kind of lexer
      text = IO.read(file).sub(/^__END__.*/m, "")
      YAML.load(text)
    end

    def lex(file)
      yaml = {}
      source = IO.read(file).sub(/^__END__.*/m, "")
      YAML.load(source).each { |k,v|
        if k == "include"
          includes = v.is_a?(String) ? [v] : v
          includes.each { |f| Lexer.load_yaml(search f).each { |k,v| yaml[k] = v } }
        else
          yaml[k] = v
        end
      }
      yaml
    end

    def search(file)
      case file
        when /^\.\.\/(.*)/; reldirs.map { |d| "#{d}/../#$1" }.find { |f| File.exist? f }
        when /^\.\/(.*)/; reldirs.map { |d| "#{d}/#$1" }.find { |f| File.exist? f }
        when /^\//; File.exist?(file) && file
      else
        absdirs.map { |d| "#{d}/#{file}" }.find { |f| File.exist? f }
      end or raise Error, "Can't find #{file}"
    end
  end
end

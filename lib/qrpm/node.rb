
module Qrpm 
  class Node
    attr_reader :directory # Destination directory
    attr_reader :name # Defaults to last element of file/link
    def path() "#{directory}/#{name}" end

    def initialize(directory, name)
      @directory, @name = directory, name
    end

    def file?() self.class == File end
    def link?() self.class == Node end

    def dump(&block)
      puts self.class
      indent { 
        puts "directory: #{directory}"
        puts "name     : #{name}"
        yield if block_given?
      }
    end
  end

  class File < Node
    attr_reader :file # Path to file in the source repository
    attr_reader :perm # Defaults to nil - using the current permissions
    def initialize(directory, name, file, perm = nil)
      super(directory, name || file.sub(/.*\//, ""))
      @file, @perm = file, perm
    end
    def dump
      super {
        puts "file     : #{file}"
        puts "perm     : #{perm}"
      }
    end
  end

  class Link < Node
    attr_reader :link # Destination file of link
    def initialize(directory, name, link)
      super(directory, name || link.sub(/.*\//, ""))
      @link = link
    end
    def dump
      super {
        puts "link     : #{link}"
      }
    end
  end
end


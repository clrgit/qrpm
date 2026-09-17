require 'open3'

module Qrpm
  # Get full name of user, defaults to username '@' hostname
  def self.fullname
    s = Etc.getpwnam(ENV['USER'])&.gecos
    if s.nil? || s == ""
      s = "#{ENV['USER']}@#{ENV['HOSTNAME']}"
    end
    s
  end

  # Matches a git tag or branch name that looks like a version. Accepts an
  # optional prefix like 'release-' or 'release/', an optional 'v', a numeric
  # core like 1.2.3, an optional pre-release suffix like -rc1 or .beta2, and
  # optional build metadata after a '+'
  VERSION_RE = %r{
    \A
    (?:[a-zA-Z][a-zA-Z_-]*[-_/])?                   # release-, rel_, release/
    [vV]?
    (?<core>\d+(?:\.\d+)*)                          # 1, 1.2, 1.2.3, ...
    (?:[-._]?(?<pre>(?:rc|alpha|beta|pre|dev|a|b)[-._]?\d*))?
    (?:\+[\w.-]+)?
    \z
  }xi

  # Parse a tag or branch name and return an array of [rpm version, sort key]
  # or nil if the name doesn't look like a version. Pre-release suffixes are
  # separated with '~' in the RPM version so that rpm orders them before the
  # final version
  def self.parse_version(name)
    m = VERSION_RE.match(name) or return nil
    pre = m[:pre]&.gsub(/[-_.]/, "")
    version = pre ? "#{m[:core]}~#{pre}" : m[:core]
    key = Gem::Version.new(pre ? "#{m[:core]}.#{pre}" : m[:core])
    [version, key]
  end

  # Matches a version-like token in a file. A dot is required so that a plain
  # number is not mistaken for a version
  FILE_VERSION_RE = /[vV]?\d+(?:\.\d+)+(?:[-._]?(?:rc|alpha|beta|pre|dev|a|b)[-._]?\d*)?(?![\w.])/i

  # Matches a version assignment like VERSION = "1.2.3", __version__ = '1.2.3',
  # version = "1.2.3" or "version": "1.2.3"
  FILE_VERSION_ASSIGNMENT_RE = /version[\W_]{0,6}(?<version>#{FILE_VERSION_RE.source})/i

  # Scan +file+ for a version and return it as an RPM version. The first
  # version that follows the word 'version' wins, as in VERSION = "1.2.3",
  # so that other dotted numbers in the file are skipped. If there is none,
  # the first version-like token in the file is used. Returns nil if none is
  # found
  def self.file_version(file)
    text = IO.read(file)
    version =
        if (m = FILE_VERSION_ASSIGNMENT_RE.match(text))
          m[:version]
        elsif (m = FILE_VERSION_RE.match(text))
          m[0]
        end
    version && parse_version(version)&.first
  end

  # Translate a chmod(1) symbolic mode like 'u=rwx,go=rx' to a four-digit
  # octal string. The mode is computed from an initial mode of 0 so only '='
  # and '+' operations are meaningful, '-' is an error. 'X' is not supported
  # because it depends on the file. Raises ArgumentError on illegal modes
  def self.chmod_to_octal(mode)
    bits = { "r" => 4, "w" => 2, "x" => 1 }
    result = 0
    mode.split(",").each { |clause|
      clause =~ /\A([ugoa]*)([-+=])([rwxst]*)\z/ or raise ArgumentError, "Illegal mode '#{clause}'"
      who, op, perms = $1, $2, $3
      op != "-" or raise ArgumentError, "Can't use '-' in '#{clause}', the initial mode is 0"
      who = "a" if who.empty?
      who = "ugo" if who.include?("a")
      who.each_char { |w|
        shift = { "u" => 6, "g" => 3, "o" => 0 }[w]
        mask = 7 << shift
        value = perms.each_char.sum { |p| bits[p] || 0 } << shift
        result = op == "=" ? (result & ~mask) | value : result | value
        result |= 04000 if w == "u" && perms.include?("s")
        result |= 02000 if w == "g" && perms.include?("s")
      }
      result |= 01000 if perms.include?("t")
    }
    sprintf "%04o", result
  end

  # Search the git history of +dir+ for a version. The highest version among
  # the tags reachable from HEAD wins. If there is none, the name of the
  # current branch is used if it looks like a version. Returns nil if no
  # version is found or if +dir+ is not in a git repository
  def self.git_version(dir)
    tags, _stderr, status = Open3.capture3("git", "-C", dir, "tag", "--merged", "HEAD")
    versions = status.success? ? tags.lines.map(&:chomp).map { |t| parse_version(t) }.compact : []
    return versions.max_by(&:last).first if !versions.empty?
    branch, _stderr, status = Open3.capture3("git", "-C", dir, "symbolic-ref", "--short", "-q", "HEAD")
    status.success? ? parse_version(branch.chomp)&.first : nil
  end

  # Return the directory that +path+ resolves to on this system if +path+ is
  # a symbolic link and +path+ itself otherwise. Used to detect merged /usr
  # systems where /bin is a link to /usr/bin
  def self.resolve_dir(path)
    File.symlink?(path) ? File.realpath(path) : path
  rescue SystemCallError
    path
  end

  # True if the git repository has uncommitted changes to tracked files below
  # +dir+. Changes elsewhere in the repository and untracked files are ignored.
  # A directory that is not part of a git repository is not dirty
  def self.dirty?(dir)
    stdout, _stderr, _status = Open3.capture3("git", "-C", dir, "status", "--porcelain", "--", ".")
    stdout.lines.any? { |line| !line.start_with?("??") }
  end
end

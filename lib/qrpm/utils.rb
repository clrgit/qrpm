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

  # Matches the first version-like token in a file. A dot is required so that
  # a plain number is not mistaken for a version
  FILE_VERSION_RE = /[vV]?\d+(?:\.\d+)+(?:[-._]?(?:rc|alpha|beta|pre|dev|a|b)[-._]?\d*)?(?![\w.])/i

  # Scan +file+ for the first occurrence of something that looks like a
  # version and return it as an RPM version. Returns nil if none is found
  def self.file_version(file)
    m = FILE_VERSION_RE.match(IO.read(file)) or return nil
    parse_version(m[0])&.first
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

  # True if the git repository has uncommitted changes to tracked files below
  # +dir+. Changes elsewhere in the repository and untracked files are ignored.
  # A directory that is not part of a git repository is not dirty
  def self.dirty?(dir)
    stdout, _stderr, _status = Open3.capture3("git", "-C", dir, "status", "--porcelain", "--", ".")
    stdout.lines.any? { |line| !line.start_with?("??") }
  end
end

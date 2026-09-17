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

  # True if the git repository has uncommitted changes to tracked files below
  # +dir+. Changes elsewhere in the repository and untracked files are ignored.
  # A directory that is not part of a git repository is not dirty
  def self.dirty?(dir)
    stdout, _stderr, _status = Open3.capture3("git", "-C", dir, "status", "--porcelain", "--", ".")
    stdout.lines.any? { |line| !line.start_with?("??") }
  end
end

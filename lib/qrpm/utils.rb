module Qrpm
  # Get full name of user, defaults to username '@' hostname
  def self.fullname
    s = Etc.getpwnam(ENV['USER'])&.gecos
    if s.nil? || s == ""
      s = "#{ENV['USER']}@#{ENV['HOSTNAME']}"
    end
    s
  end
end

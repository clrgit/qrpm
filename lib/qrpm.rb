# frozen_string_literal: true

require "constrain"

require_relative "qrpm/version"
require_relative "qrpm/node.rb"
require_relative "qrpm/rpm.rb"
require_relative "qrpm/parser.rb"
require_relative "qrpm/qrpm.rb"
require_relative "qrpm/fragment.rb"

  include Constrain
module Qrpm

  class Error < RuntimeError; end

  QRPM_CONFIG_FILE = "qrpm.yml"

  QRPM_SHARE_DIR = "#{::File.dirname(__FILE__)}/../lib/qrpm"
  QRPM_CONFIG_FILE_TEMPLATE = "#{QRPM_SHARE_DIR}/template.yml"
  QRPM_ERB_FILE = "#{QRPM_SHARE_DIR}/template.erb"

  MANDATORY_FIELDS = %w(name summary version)

  OPTIONAL_FIELDS = {
    "requires" => []
  }
    
  USED_FIELDS = MANDATORY_FIELDS + OPTIONAL_FIELDS.keys

  SYSTEM_DIRS = {
    "etcdir" => "/etc",
    "bindir" => "/usr/bin",
    "sbindir" => "/usr/sbin",
    "libdir" => "/usr/lib",
    "libexecdir" => "/usr/libexec",
    "sharedir" => "/usr/share",
    "vardir" => "/var/lib",
    "spooldir" => "/var/spool",
    "rundir" => "/var/run",
    "lockdir" => "/var/lock",
    "cachedir" => "/var/cache",
    "tmpdir" => "/tmp",
    "logdir" => "/var/log"
  }
end

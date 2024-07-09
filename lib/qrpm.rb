# frozen_string_literal: true

require 'etc'

require 'indented_io'
require "constrain"
require "forward_to"

include Constrain
include ForwardTo

require_relative "qrpm/version"
require_relative "qrpm/node.rb"
require_relative "qrpm/fragment.rb"
require_relative "qrpm/lexer.rb"
require_relative "qrpm/compiler.rb"
require_relative "qrpm/qrpm.rb"
require_relative "qrpm/rpm.rb"
require_relative "qrpm/utils.rb"

module Qrpm
  class Error < RuntimeError; end
  class CompileError < StandardError; end
  class AbstractMethodError < StandardError; end
  def abstract_method = raise AbstractMethodError.new "Abstract method called"

  QRPM_CONFIG_FILE = "qrpm.yml"

  QRPM_SHARE_DIR = "#{::File.dirname(__FILE__)}/../lib/qrpm"
  QRPM_CONFIG_FILE_TEMPLATE = "#{QRPM_SHARE_DIR}/template.yml"
  QRPM_ERB_FILE = "#{QRPM_SHARE_DIR}/template.erb"

  # Should be defined and non-empty
  MANDATORY_FIELDS = Rpm::MANDATORY_FIELDS

  # Maps from field name to array of allowed types for that field
  FIELDS = Rpm::FIELDS.map { |k,ts|
    nts = ts.map { |t|
      if t == String
        ValueNode
      elsif t == Array
        ArrayNode
      else
        raise ArgumentError, "Illegal type: #{t.inspect}"
      end
    }
    [k, nts]
  }.to_h

  STANDARD_DIRS = %w(
    etcdir bindir sbindir libdir libexecdir sharedir docdir vardir spooldir
    rundir lockdir cachedir logdir tmpdir
  )

  ROOT_DIRS = {
    rootdir: "/",
    rootconfdir: "$rootdir/etc",
    rootexecdir: "$rootdir/usr",
    rootlibdir: "$rootdir/usr",
    rootconstdir: "$rootdir/usr/share",
    rootdocdir: "$rootconstdir",
    rootdatadir: "$rootdir/var"
  }

  SYSTEM_DIRS = {
    sysetcdir: "$rootconfdir",
    sysbindir: "$rootexecdir/bin",
    syssbindir: "$rootexecdir/sbin",
    syslibdir: "$rootlibdir/lib64",
    syslibexecdir: "$rootexecdir/libexec",
    syssharedir: "$rootconstdir",
    sysdocdir: "$syssharedir/doc",
    sysvardir: "$rootdatadir/lib",
    sysspooldir: "$rootdatadir/spool",
    sysrundir: "$rootdatadir/run",
    syslockdir: "$rootdatadir/lock",
    syscachedir: "$rootdatadir/cache",
    syslogdir: "$rootdatadir/log",
    systmpdir: "/tmp" # Always /tmp because of security
  }

  PACKAGE_DIRS = {
    pcketcdir: "$sysetcdir/$pckdir",
    pckbindir: "$sysbindir", # No package-specific directory
    pcksbindir: "$syssbindir", # No package-specific directory
    pcklibdir: "$syslibdir/$pckdir",
    pcklibexecdir: "$syslibexecdir/$pckdir",
    pcksharedir: "$syssharedir/$pckdir",
    pckdocdir: "$sysdocdir/$pckdir",
    pckvardir: "$sysvardir/$pckdir",
    pckspooldir: "$sysspooldir/$pckdir",
    pckrundir: "$sysrundir/$pckdir",
    pcklockdir: "$syslockdir/$pckdir",
    pckcachedir: "$syscachedir/$pckdir",
    pcklogdir: "$syslogdir/$pckdir",
    pcktmpdir: "$systmpdir/$pckdir"
  }

  INSTALL_DIRS = ROOT_DIRS.merge SYSTEM_DIRS.merge PACKAGE_DIRS

  DEFAULTS = {
    "name" => "$(basename $PWD)",
    "summary" => "The $name RPM package",
    "version" => "$(cd ${{srcdir}} >/dev/null && git tag -l 2>/dev/null | sort -V | tail -1 | tr -dc '.0-9' || echo 0.0.0)",
    "description" => "$summary",
    "release" => "1",
    "license" => "GPL",
    "packager" => ::Qrpm.fullname,
    "currdir" => ".", # The directory from where the qrpm was run. Initialized by the client program
    "qrpmdir" => ".", # The directory containing the qrpm file. Initialized by the client program
    "srcdir" => ".",
    "pckdir" => "$name",
    "make" => nil
  }

  IDENT_RE = /(?:[\w_][\w\d_]*)/
  PATH_RE = /(?:[\w_][\w\d_.]*)/

  FILE_KEYS = %w(name file symlink reflink perm)
end


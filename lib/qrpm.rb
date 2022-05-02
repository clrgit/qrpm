# frozen_string_literal: true

require_relative "qrpm/version"
require_relative "qrpm/node.rb"
require_relative "qrpm/rpm.rb"
require_relative "qrpm/parser.rb"

module Qrpm
  class Error < RuntimeError; end

  QRPM_CONFIG_FILE = "qrpm.yml"

  QRPM_SHARE_DIR = "#{::File.dirname(__FILE__)}/../lib/qrpm"
  QRPM_CONFIG_FILE_TEMPLATE = "#{QRPM_SHARE_DIR}/template.yml"
  QRPM_ERB_FILE = "#{QRPM_SHARE_DIR}/template.erb"
end

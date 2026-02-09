# frozen_string_literal: true

require_relative 'authsnitch/client'
require_relative 'authsnitch/diff_analyzer'
require_relative 'authsnitch/detector'
require_relative 'authsnitch/risk_scorer'
require_relative 'authsnitch/summarizer'
require_relative 'authsnitch/notifier'

module Authsnitch
  VERSION = '1.0.0'

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class APIError < Error; end
end

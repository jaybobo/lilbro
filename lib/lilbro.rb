# frozen_string_literal: true

require_relative 'lilbro/client'
require_relative 'lilbro/diff_analyzer'
require_relative 'lilbro/detector'
require_relative 'lilbro/risk_scorer'
require_relative 'lilbro/summarizer'
require_relative 'lilbro/notifier'

module Lilbro
  VERSION = '1.0.0'

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class APIError < Error; end
end

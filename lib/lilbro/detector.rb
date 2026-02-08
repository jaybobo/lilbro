# frozen_string_literal: true

require 'anthropic'
require 'yaml'
require 'json'

module Lilbro
  # Claude-powered detection engine for analyzing PR diffs
  class Detector
    DEFAULT_CONFIG_PATH = File.expand_path('../../config/detection.yml', __dir__)

    Finding = Struct.new(
      :type, :file, :code_section, :description,
      :security_relevance, :risk_level, :recommendation,
      keyword_init: true
    )

    DetectionResult = Struct.new(
      :findings, :summary, :auth_changes_detected, :highest_risk, :raw_response,
      keyword_init: true
    )

    attr_reader :config, :client

    def initialize(api_key:, config_path: nil, custom_keywords: nil, custom_prompt: nil)
      @client = Anthropic::Client.new(access_token: api_key)
      @config = load_config(config_path)
      @custom_keywords = custom_keywords
      @custom_prompt = custom_prompt
    end

    # Analyze diff content for authentication-related changes
    # @param diff_content [String] Formatted diff content from DiffAnalyzer
    # @param file_changes [Array<DiffAnalyzer::FileChange>] Parsed file changes for context
    # @return [DetectionResult] Structured detection results
    def analyze(diff_content, file_changes: [])
      return empty_result if diff_content.nil? || diff_content.strip.empty?

      prompt = build_prompt(diff_content, file_changes)
      response = call_claude(prompt)
      parse_response(response)
    end

    # Get all keywords as a flat list for display
    # @return [Array<String>]
    def all_keywords
      keywords = []
      config['keywords']&.each_value do |category_keywords|
        keywords.concat(Array(category_keywords))
      end
      keywords.concat(parse_custom_keywords) if @custom_keywords
      keywords.uniq
    end

    private

    def load_config(custom_path)
      path = custom_path || DEFAULT_CONFIG_PATH

      if custom_path && File.exist?(custom_path)
        custom_config = YAML.safe_load(File.read(custom_path))
        default_config = YAML.safe_load(File.read(DEFAULT_CONFIG_PATH))
        deep_merge(default_config, custom_config)
      elsif File.exist?(path)
        YAML.safe_load(File.read(path))
      else
        { 'keywords' => {}, 'detection_prompt' => default_prompt }
      end
    end

    def deep_merge(base, overlay)
      base.merge(overlay) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        elsif old_val.is_a?(Array) && new_val.is_a?(Array)
          (old_val + new_val).uniq
        else
          new_val
        end
      end
    end

    def build_prompt(diff_content, file_changes)
      prompt_template = @custom_prompt || config['detection_prompt'] || default_prompt
      keywords_text = format_keywords

      # Add file context
      file_context = ""
      auth_files = file_changes.select(&:auth_sensitive)
      unless auth_files.empty?
        file_context = "\n\nAuth-sensitive files detected:\n"
        file_context += auth_files.map { |f| "- #{f.filename}" }.join("\n")
      end

      prompt = prompt_template.gsub('{keywords}', keywords_text)

      <<~PROMPT
        #{prompt}

        #{file_context}

        === CODE DIFF ===
        #{diff_content}
        === END DIFF ===
      PROMPT
    end

    def format_keywords
      all_keywords.join(', ')
    end

    def parse_custom_keywords
      return [] unless @custom_keywords

      @custom_keywords.split(',').map(&:strip).reject(&:empty?)
    end

    def call_claude(prompt)
      defaults = load_defaults

      response = client.messages.create(
        model: defaults.dig('claude', 'model') || 'claude-sonnet-4-20250514',
        max_tokens: defaults.dig('claude', 'max_tokens') || 4096,
        messages: [
          { role: 'user', content: prompt }
        ]
      )

      response.content.first.text
    end

    def load_defaults
      defaults_path = File.expand_path('../../config/defaults.yml', __dir__)
      return {} unless File.exist?(defaults_path)

      YAML.safe_load(File.read(defaults_path))
    end

    def parse_response(response_text)
      # Try to extract JSON from the response
      json_text = extract_json(response_text)
      data = JSON.parse(json_text)

      findings = (data['findings'] || []).map do |f|
        Finding.new(
          type: f['type'],
          file: f['file'],
          code_section: f['code_section'],
          description: f['description'],
          security_relevance: f['security_relevance'],
          risk_level: f['risk_level']&.downcase || 'none',
          recommendation: f['recommendation']
        )
      end

      DetectionResult.new(
        findings: findings,
        summary: data['summary'] || 'Analysis complete.',
        auth_changes_detected: data['auth_changes_detected'] || false,
        highest_risk: data['highest_risk']&.downcase || 'none',
        raw_response: response_text
      )
    rescue JSON::ParserError => e
      # If JSON parsing fails, create a result indicating an error
      DetectionResult.new(
        findings: [],
        summary: "Failed to parse Claude response: #{e.message}",
        auth_changes_detected: false,
        highest_risk: 'none',
        raw_response: response_text
      )
    end

    def extract_json(text)
      # Try to find JSON in the response (handle markdown code blocks)
      if text.include?('```json')
        text.match(/```json\s*(.*?)\s*```/m)&.captures&.first || text
      elsif text.include?('```')
        text.match(/```\s*(.*?)\s*```/m)&.captures&.first || text
      else
        text.strip
      end
    end

    def empty_result
      DetectionResult.new(
        findings: [],
        summary: 'No diff content provided for analysis.',
        auth_changes_detected: false,
        highest_risk: 'none',
        raw_response: nil
      )
    end

    def default_prompt
      <<~PROMPT
        You are a security code reviewer. Analyze the provided code diff for authentication-related changes.
        Look for: {keywords}
        Return findings as JSON.
      PROMPT
    end
  end
end

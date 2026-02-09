#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'json'
require_relative 'lib/authsnitch'

# Main entrypoint for the AuthSnitch GitHub Action
class Entrypoint
  def initialize
    @github_token = ENV.fetch('GITHUB_TOKEN') { raise 'GITHUB_TOKEN is required' }
    @anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY') { raise 'ANTHROPIC_API_KEY is required' }

    # Notification settings
    @slack_webhook_url = ENV['SLACK_WEBHOOK_URL']
    @teams_webhook_url = ENV['TEAMS_WEBHOOK_URL']
    @post_pr_comment = ENV['POST_PR_COMMENT']&.downcase == 'true'

    # Thresholds
    @risk_threshold = (ENV['RISK_THRESHOLD'] || '50').to_i
    @pr_comment_threshold = ENV['PR_COMMENT_THRESHOLD']&.to_i
    @slack_threshold = ENV['SLACK_THRESHOLD']&.to_i
    @teams_threshold = ENV['TEAMS_THRESHOLD']&.to_i

    # Customization
    @custom_keywords = ENV['CUSTOM_KEYWORDS']
    @detection_prompt = ENV['DETECTION_PROMPT']
    @detection_config_path = ENV['DETECTION_CONFIG_PATH']
  end

  def run
    log 'AuthSnitch Security Review starting...'

    # Get PR context from GitHub Actions environment
    pr_context = Authsnitch::Client.pr_context_from_env
    unless pr_context
      log 'Not a pull request event or missing context. Skipping.'
      exit 0
    end

    repo = pr_context[:repo]
    pr_number = pr_context[:pr_number]
    log "Analyzing PR ##{pr_number} in #{repo}"

    # Initialize components
    github_client = Authsnitch::Client.new(token: @github_token)
    diff_analyzer = Authsnitch::DiffAnalyzer.new
    detector = Authsnitch::Detector.new(
      api_key: @anthropic_api_key,
      config_path: resolve_config_path,
      custom_keywords: @custom_keywords,
      custom_prompt: @detection_prompt
    )
    risk_scorer = Authsnitch::RiskScorer.new
    notifier = Authsnitch::Notifier.new(github_client: github_client)

    # Fetch PR data
    log 'Fetching PR metadata and diff...'
    pr_data = github_client.pull_request(repo: repo, pr_number: pr_number)
    files = github_client.pull_request_files(repo: repo, pr_number: pr_number)

    # Parse the diff
    file_changes = diff_analyzer.parse_files(files)
    diff_content = diff_analyzer.extract_changes_for_analysis(file_changes)

    log "Found #{file_changes.length} changed files (#{diff_analyzer.count_auth_sensitive_files(file_changes)} auth-sensitive)"

    # Skip if no changes to analyze
    if diff_content.strip.empty?
      log 'No code changes to analyze. Exiting.'
      exit 0
    end

    # Run detection
    log 'Running Claude detection analysis...'
    detection_result = detector.analyze(diff_content, file_changes: file_changes)

    if detection_result.auth_changes_detected
      log "Auth changes detected! Highest risk: #{detection_result.highest_risk}"
    else
      log 'No authentication-related changes detected.'
    end

    # Calculate risk score
    score_result = risk_scorer.calculate(detection_result, file_changes: file_changes)
    log "Risk score: #{score_result[:score]} (#{score_result[:label]})"

    # Build PR info
    pr_info = {
      title: pr_data.title,
      number: pr_number,
      author: pr_data.user&.login,
      repo: repo,
      url: pr_data.html_url
    }

    # Detect keywords in the diff
    keywords_detected = detect_keywords(diff_content, detector.all_keywords)

    # Send notifications
    notification_config = {
      post_pr_comment: @post_pr_comment,
      pr_comment_threshold: @pr_comment_threshold,
      slack_webhook_url: @slack_webhook_url,
      slack_threshold: @slack_threshold,
      teams_webhook_url: @teams_webhook_url,
      teams_threshold: @teams_threshold,
      risk_threshold: @risk_threshold
    }

    log 'Sending notifications...'
    results = notifier.notify_all(
      detection_result: detection_result,
      score_result: score_result,
      pr_info: pr_info,
      keywords_detected: keywords_detected,
      config: notification_config
    )

    # Log notification results
    results.each do |channel, result|
      if result[:skipped]
        log "  #{channel}: Skipped (#{result[:reason]})"
      elsif result[:success]
        log "  #{channel}: Sent successfully"
      else
        log "  #{channel}: Failed (#{result[:error]})"
      end
    end

    # Output summary
    output_summary(detection_result, score_result)

    log 'AuthSnitch Security Review complete.'
  end

  private

  def resolve_config_path
    return nil if @detection_config_path.nil? || @detection_config_path.empty?

    # Check if path exists in the workspace
    workspace = ENV['GITHUB_WORKSPACE'] || '.'
    full_path = File.join(workspace, @detection_config_path)

    File.exist?(full_path) && File.file?(full_path) ? full_path : nil
  end

  def detect_keywords(content, keywords)
    content_lower = content.downcase
    keywords.select { |kw| content_lower.include?(kw.downcase) }
  end

  def output_summary(detection_result, score_result)
    # Set GitHub Actions outputs
    set_output('risk_score', score_result[:score])
    set_output('risk_label', score_result[:label])
    set_output('auth_changes_detected', detection_result.auth_changes_detected)
    set_output('findings_count', detection_result.findings.length)
    set_output('summary', detection_result.summary)
  end

  def set_output(name, value)
    output_file = ENV['GITHUB_OUTPUT']
    return unless output_file

    File.open(output_file, 'a') do |f|
      f.puts "#{name}=#{value}"
    end
  end

  def log(message)
    puts "[AuthSnitch] #{message}"
  end
end

# Run the action
Entrypoint.new.run

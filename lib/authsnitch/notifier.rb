# frozen_string_literal: true

require 'erb'
require 'faraday'
require 'json'

module Authsnitch
  # Sends notifications to various channels (Slack, Teams, PR comments)
  class Notifier
    ALERT_COLOR = '#ff9800'
    TEMPLATES_DIR = File.expand_path('../../../config/templates', __FILE__)

    attr_reader :github_client, :summarizer

    def initialize(github_client:)
      @github_client = github_client
      @summarizer = Summarizer.new
    end

    # Send notifications to all configured channels based on should_notify boolean
    # @param detection_result [Detector::DetectionResult] Detection result
    # @param should_notify [Boolean] Whether to send notifications
    # @param pr_info [Hash] PR metadata
    # @param keywords_detected [Array<String>] Keywords found
    # @param config [Hash] Notification configuration
    # @return [Hash] Results for each channel
    def notify_all(detection_result:, should_notify:, pr_info:, keywords_detected:, config:)
      summary = summarizer.summarize(
        detection_result: detection_result,
        pr_info: pr_info,
        keywords_detected: keywords_detected,
        should_notify: should_notify
      )

      results = {}

      unless should_notify
        results[:pr_comment] = { skipped: true, reason: 'Notification not triggered' } if config[:post_pr_comment]
        results[:slack] = { skipped: true, reason: 'Notification not triggered' } if config[:slack_webhook_url]
        results[:teams] = { skipped: true, reason: 'Notification not triggered' } if config[:teams_webhook_url]
        return results
      end

      # PR Comment
      if config[:post_pr_comment]
        results[:pr_comment] = post_pr_comment(summary, pr_info)
      end

      # Slack
      if config[:slack_webhook_url]
        results[:slack] = send_slack(summary, pr_info, config[:slack_webhook_url])
      end

      # Teams
      if config[:teams_webhook_url]
        results[:teams] = send_teams(summary, pr_info, config[:teams_webhook_url])
      end

      results
    end

    # Post a comment on the PR
    # @param summary [Hash] Formatted summary
    # @param pr_info [Hash] PR metadata
    # @return [Hash] Result with success status
    def post_pr_comment(summary, pr_info)
      markdown = render_template('github_pr_comment.md.erb', summary, pr_info)

      github_client.create_pr_comment(
        repo: pr_info[:repo],
        pr_number: pr_info[:number],
        body: markdown
      )

      { success: true, channel: 'pr_comment' }
    rescue StandardError => e
      { success: false, channel: 'pr_comment', error: e.message }
    end

    # Send Slack notification using Block Kit format
    # @param summary [Hash] Formatted summary
    # @param pr_info [Hash] PR metadata
    # @param webhook_url [String] Slack webhook URL
    # @return [Hash] Result with success status
    def send_slack(summary, pr_info, webhook_url)
      payload = JSON.parse(render_template('slack.json.erb', summary, pr_info))

      response = Faraday.post(webhook_url) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = payload.to_json
      end

      if response.success?
        { success: true, channel: 'slack' }
      else
        { success: false, channel: 'slack', error: "HTTP #{response.status}: #{response.body}" }
      end
    rescue StandardError => e
      { success: false, channel: 'slack', error: e.message }
    end

    # Send Teams notification using MessageCard format
    # @param summary [Hash] Formatted summary
    # @param pr_info [Hash] PR metadata
    # @param webhook_url [String] Teams webhook URL
    # @return [Hash] Result with success status
    def send_teams(summary, pr_info, webhook_url)
      payload = JSON.parse(render_template('teams.json.erb', summary, pr_info))

      response = Faraday.post(webhook_url) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = payload.to_json
      end

      if response.success?
        { success: true, channel: 'teams' }
      else
        { success: false, channel: 'teams', error: "HTTP #{response.status}: #{response.body}" }
      end
    rescue StandardError => e
      { success: false, channel: 'teams', error: e.message }
    end

    private

    def render_template(template_name, summary, pr_info)
      template_path = File.join(TEMPLATES_DIR, template_name)
      template = ERB.new(File.read(template_path), trim_mode: '-')
      b = binding
      b.local_variable_set(:summary, summary)
      b.local_variable_set(:pr_info, pr_info)
      template.result(b)
    end

    def truncate(text, max_length)
      return text if text.nil? || text.length <= max_length

      "#{text[0, max_length - 3]}..."
    end
  end
end

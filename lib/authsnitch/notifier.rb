# frozen_string_literal: true

require 'faraday'
require 'json'

module Authsnitch
  # Sends notifications to various channels (Slack, Teams, PR comments)
  class Notifier
    ALERT_COLOR = '#ff9800'

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
      markdown = summarizer.to_markdown(summary)

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
      payload = build_slack_payload(summary, pr_info)

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
      payload = build_teams_payload(summary, pr_info)

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

    def build_slack_payload(summary, pr_info)
      blocks = []

      # Header
      blocks << {
        type: 'header',
        text: {
          type: 'plain_text',
          text: summary[:title],
          emoji: true
        }
      }

      # Signal Summary
      signal_parts = []
      signal_parts << "Claude: Detected" if summary[:findings].any?
      signal_parts << "Keywords: #{summary[:keywords].join(', ')}" if summary[:keywords].any?

      if signal_parts.any?
        blocks << {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "*Signals:* #{signal_parts.join(' | ')}"
          }
        }
      end

      # Divider
      blocks << { type: 'divider' }

      # PR Info Section
      if pr_info[:title]
        blocks << {
          type: 'section',
          fields: [
            {
              type: 'mrkdwn',
              text: "*PR:* ##{pr_info[:number]} \"#{pr_info[:title]}\""
            },
            {
              type: 'mrkdwn',
              text: "*Author:* #{pr_info[:author] || 'Unknown'}"
            },
            {
              type: 'mrkdwn',
              text: "*Repository:* #{pr_info[:repo]}"
            }
          ]
        }
      end

      # Divider
      blocks << { type: 'divider' }

      # Summary Section
      blocks << {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*Summary:*\n#{truncate(summary[:summary], 500)}"
        }
      }

      # Files Affected
      if summary[:files_affected].any?
        files_text = summary[:files_affected].first(5).map { |f| "• `#{f}`" }.join("\n")
        files_text += "\n_...and #{summary[:files_affected].length - 5} more_" if summary[:files_affected].length > 5

        blocks << {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "*Files Affected:*\n#{files_text}"
          }
        }
      end

      # Keywords Detected
      if summary[:keywords].any?
        keywords_text = summary[:keywords].first(10).map { |k| "`#{k}`" }.join(', ')
        blocks << {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "*Keywords Detected:* #{keywords_text}"
          }
        }
      end

      # Divider
      blocks << { type: 'divider' }

      # Action Buttons
      if pr_info[:url]
        blocks << {
          type: 'actions',
          elements: [
            {
              type: 'button',
              text: {
                type: 'plain_text',
                text: 'View PR',
                emoji: true
              },
              url: pr_info[:url],
              style: 'primary'
            },
            {
              type: 'button',
              text: {
                type: 'plain_text',
                text: 'View Diff',
                emoji: true
              },
              url: "#{pr_info[:url]}/files"
            }
          ]
        }
      end

      {
        attachments: [
          {
            color: ALERT_COLOR,
            blocks: blocks
          }
        ]
      }
    end

    def build_teams_payload(summary, pr_info)
      # Build facts for PR info
      facts = []
      signal_parts = []
      signal_parts << "Claude: Detected" if summary[:findings].any?
      signal_parts << "Keywords: #{summary[:keywords].join(', ')}" if summary[:keywords].any?
      facts << { title: 'Signals', value: signal_parts.join(' | ') } if signal_parts.any?
      facts << { title: 'PR', value: "##{pr_info[:number]} - #{pr_info[:title]}" } if pr_info[:title]
      facts << { title: 'Author', value: pr_info[:author] } if pr_info[:author]
      facts << { title: 'Repository', value: pr_info[:repo] } if pr_info[:repo]

      if summary[:files_affected].any?
        files_text = summary[:files_affected].first(5).join(', ')
        files_text += "... +#{summary[:files_affected].length - 5} more" if summary[:files_affected].length > 5
        facts << { title: 'Files Affected', value: files_text }
      end

      if summary[:keywords].any?
        facts << { title: 'Keywords', value: summary[:keywords].first(10).join(', ') }
      end

      # Build actions
      actions = []
      if pr_info[:url]
        actions << {
          '@type': 'OpenUri',
          name: 'View PR',
          targets: [{ os: 'default', uri: pr_info[:url] }]
        }
        actions << {
          '@type': 'OpenUri',
          name: 'View Diff',
          targets: [{ os: 'default', uri: "#{pr_info[:url]}/files" }]
        }
      end

      {
        '@type': 'MessageCard',
        '@context': 'http://schema.org/extensions',
        themeColor: ALERT_COLOR.delete('#'),
        summary: summary[:title],
        sections: [
          {
            activityTitle: summary[:title],
            activitySubtitle: pr_info[:repo],
            facts: facts,
            text: truncate(summary[:summary], 500),
            markdown: true
          }
        ],
        potentialAction: actions
      }
    end

    def truncate(text, max_length)
      return text if text.nil? || text.length <= max_length

      "#{text[0, max_length - 3]}..."
    end
  end
end

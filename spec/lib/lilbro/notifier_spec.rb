# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Lilbro::Notifier do
  let(:github_client) { instance_double(Lilbro::Client) }
  subject(:notifier) { described_class.new(github_client: github_client) }

  let(:detection_result) do
    Lilbro::Detector::DetectionResult.new(
      findings: [
        Lilbro::Detector::Finding.new(
          type: 'session_handling',
          file: 'app/controllers/sessions_controller.rb',
          code_section: 'session[:user_id] = user.id',
          description: 'Session assignment change',
          security_relevance: 'Affects user authentication',
          risk_level: 'medium',
          recommendation: 'Review session configuration'
        )
      ],
      summary: 'Session handling changes detected.',
      auth_changes_detected: true,
      highest_risk: 'medium',
      raw_response: nil
    )
  end

  let(:score_result) do
    {
      score: 55,
      label: 'HIGH',
      color: '#ff9800',
      breakdown: {
        base_score: 40,
        highest_risk: 'medium',
        modifiers: [
          { name: 'multiple_auth_files', points: 15, reason: '3 auth-sensitive files' }
        ],
        modifier_total: 15
      }
    }
  end

  let(:pr_info) do
    {
      title: 'Update session handling',
      number: 456,
      author: 'developer',
      repo: 'org/repo',
      url: 'https://github.com/org/repo/pull/456'
    }
  end

  describe '#notify_all' do
    context 'with PR comment enabled' do
      it 'posts comment when score exceeds threshold' do
        allow(github_client).to receive(:create_pr_comment).and_return(true)

        results = notifier.notify_all(
          detection_result: detection_result,
          score_result: score_result,
          pr_info: pr_info,
          keywords_detected: ['session'],
          config: { post_pr_comment: true, pr_comment_threshold: 50 }
        )

        expect(github_client).to have_received(:create_pr_comment)
        expect(results[:pr_comment][:success]).to be true
      end

      it 'skips comment when score is below threshold' do
        results = notifier.notify_all(
          detection_result: detection_result,
          score_result: score_result,
          pr_info: pr_info,
          keywords_detected: [],
          config: { post_pr_comment: true, pr_comment_threshold: 60 }
        )

        expect(results[:pr_comment][:skipped]).to be true
      end
    end

    context 'with Slack webhook' do
      let(:webhook_url) { 'https://hooks.slack.com/services/test' }

      it 'sends notification when score exceeds threshold' do
        stub_request(:post, webhook_url).to_return(status: 200, body: 'ok')

        results = notifier.notify_all(
          detection_result: detection_result,
          score_result: score_result,
          pr_info: pr_info,
          keywords_detected: ['session'],
          config: { slack_webhook_url: webhook_url, slack_threshold: 50 }
        )

        expect(results[:slack][:success]).to be true
        expect(WebMock).to have_requested(:post, webhook_url)
      end

      it 'skips when score is below threshold' do
        results = notifier.notify_all(
          detection_result: detection_result,
          score_result: score_result,
          pr_info: pr_info,
          keywords_detected: [],
          config: { slack_webhook_url: webhook_url, slack_threshold: 80 }
        )

        expect(results[:slack][:skipped]).to be true
      end
    end

    context 'with Teams webhook' do
      let(:webhook_url) { 'https://outlook.office.com/webhook/test' }

      it 'sends notification when score exceeds threshold' do
        stub_request(:post, webhook_url).to_return(status: 200, body: '1')

        results = notifier.notify_all(
          detection_result: detection_result,
          score_result: score_result,
          pr_info: pr_info,
          keywords_detected: ['session'],
          config: { teams_webhook_url: webhook_url, teams_threshold: 50 }
        )

        expect(results[:teams][:success]).to be true
        expect(WebMock).to have_requested(:post, webhook_url)
      end
    end

    context 'with multiple channels' do
      let(:slack_url) { 'https://hooks.slack.com/services/test' }
      let(:teams_url) { 'https://outlook.office.com/webhook/test' }

      it 'respects independent thresholds per channel' do
        allow(github_client).to receive(:create_pr_comment).and_return(true)
        stub_request(:post, slack_url).to_return(status: 200)
        stub_request(:post, teams_url).to_return(status: 200)

        results = notifier.notify_all(
          detection_result: detection_result,
          score_result: score_result,  # score is 55
          pr_info: pr_info,
          keywords_detected: [],
          config: {
            post_pr_comment: true,
            pr_comment_threshold: 30,  # should send (55 >= 30)
            slack_webhook_url: slack_url,
            slack_threshold: 50,       # should send (55 >= 50)
            teams_webhook_url: teams_url,
            teams_threshold: 70        # should skip (55 < 70)
          }
        )

        expect(results[:pr_comment][:success]).to be true
        expect(results[:slack][:success]).to be true
        expect(results[:teams][:skipped]).to be true
      end
    end
  end

  describe '#send_slack' do
    let(:webhook_url) { 'https://hooks.slack.com/services/test' }

    it 'sends Block Kit formatted message' do
      stub_request(:post, webhook_url)
        .with { |req| JSON.parse(req.body)['attachments'].is_a?(Array) }
        .to_return(status: 200)

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        score_result: score_result,
        pr_info: pr_info,
        keywords_detected: ['session']
      )

      result = notifier.send_slack(summary, pr_info, webhook_url)

      expect(result[:success]).to be true
    end

    it 'handles webhook errors gracefully' do
      stub_request(:post, webhook_url).to_return(status: 500, body: 'Error')

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        score_result: score_result,
        pr_info: pr_info,
        keywords_detected: []
      )

      result = notifier.send_slack(summary, pr_info, webhook_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('500')
    end
  end

  describe '#send_teams' do
    let(:webhook_url) { 'https://outlook.office.com/webhook/test' }

    it 'sends Adaptive Card formatted message' do
      stub_request(:post, webhook_url)
        .with { |req| JSON.parse(req.body)['@type'] == 'MessageCard' }
        .to_return(status: 200)

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        score_result: score_result,
        pr_info: pr_info,
        keywords_detected: ['session']
      )

      result = notifier.send_teams(summary, pr_info, webhook_url)

      expect(result[:success]).to be true
    end
  end
end

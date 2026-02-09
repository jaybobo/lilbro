# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authsnitch::Notifier do
  let(:github_client) { instance_double(Authsnitch::Client) }
  subject(:notifier) { described_class.new(github_client: github_client) }

  let(:detection_result) do
    Authsnitch::Detector::DetectionResult.new(
      findings: [
        Authsnitch::Detector::Finding.new(
          type: 'session_handling',
          file: 'app/controllers/sessions_controller.rb',
          code_section: 'session[:user_id] = user.id',
          description: 'Session assignment change'
        )
      ],
      summary: 'Session handling changes detected.',
      auth_changes_detected: true,
      raw_response: nil
    )
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
    context 'when should_notify is true' do
      it 'posts PR comment when configured' do
        allow(github_client).to receive(:create_pr_comment).and_return(true)

        results = notifier.notify_all(
          detection_result: detection_result,
          should_notify: true,
          pr_info: pr_info,
          keywords_detected: ['session'],
          config: { post_pr_comment: true }
        )

        expect(github_client).to have_received(:create_pr_comment)
        expect(results[:pr_comment][:success]).to be true
      end

      it 'sends Slack notification when configured' do
        webhook_url = 'https://hooks.slack.com/services/test'
        stub_request(:post, webhook_url).to_return(status: 200, body: 'ok')

        results = notifier.notify_all(
          detection_result: detection_result,
          should_notify: true,
          pr_info: pr_info,
          keywords_detected: ['session'],
          config: { slack_webhook_url: webhook_url }
        )

        expect(results[:slack][:success]).to be true
        expect(WebMock).to have_requested(:post, webhook_url)
      end

      it 'sends Teams notification when configured' do
        webhook_url = 'https://outlook.office.com/webhook/test'
        stub_request(:post, webhook_url).to_return(status: 200, body: '1')

        results = notifier.notify_all(
          detection_result: detection_result,
          should_notify: true,
          pr_info: pr_info,
          keywords_detected: ['session'],
          config: { teams_webhook_url: webhook_url }
        )

        expect(results[:teams][:success]).to be true
        expect(WebMock).to have_requested(:post, webhook_url)
      end

      it 'sends to all configured channels' do
        slack_url = 'https://hooks.slack.com/services/test'
        teams_url = 'https://outlook.office.com/webhook/test'
        allow(github_client).to receive(:create_pr_comment).and_return(true)
        stub_request(:post, slack_url).to_return(status: 200)
        stub_request(:post, teams_url).to_return(status: 200)

        results = notifier.notify_all(
          detection_result: detection_result,
          should_notify: true,
          pr_info: pr_info,
          keywords_detected: ['session'],
          config: {
            post_pr_comment: true,
            slack_webhook_url: slack_url,
            teams_webhook_url: teams_url
          }
        )

        expect(results[:pr_comment][:success]).to be true
        expect(results[:slack][:success]).to be true
        expect(results[:teams][:success]).to be true
      end
    end

    context 'when should_notify is false' do
      it 'skips all configured channels' do
        slack_url = 'https://hooks.slack.com/services/test'
        teams_url = 'https://outlook.office.com/webhook/test'

        results = notifier.notify_all(
          detection_result: detection_result,
          should_notify: false,
          pr_info: pr_info,
          keywords_detected: [],
          config: {
            post_pr_comment: true,
            slack_webhook_url: slack_url,
            teams_webhook_url: teams_url
          }
        )

        expect(results[:pr_comment][:skipped]).to be true
        expect(results[:slack][:skipped]).to be true
        expect(results[:teams][:skipped]).to be true
      end

      it 'does not make any HTTP requests' do
        slack_url = 'https://hooks.slack.com/services/test'

        notifier.notify_all(
          detection_result: detection_result,
          should_notify: false,
          pr_info: pr_info,
          keywords_detected: [],
          config: { slack_webhook_url: slack_url }
        )

        expect(WebMock).not_to have_requested(:post, slack_url)
      end
    end
  end

  describe '#post_pr_comment' do
    it 'renders the markdown template and posts it' do
      allow(github_client).to receive(:create_pr_comment).and_return(true)

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        pr_info: pr_info,
        keywords_detected: ['session'],
        should_notify: true
      )

      result = notifier.post_pr_comment(summary, pr_info)

      expect(result[:success]).to be true
      expect(github_client).to have_received(:create_pr_comment).with(
        repo: 'org/repo',
        pr_number: 456,
        body: a_string_including(
          '## AuthSnitch - Authentication Changes Detected',
          '### Summary',
          '### Findings',
          '*Generated by AuthSnitch*'
        )
      )
    end
  end

  describe '#send_slack' do
    let(:webhook_url) { 'https://hooks.slack.com/services/test' }

    it 'sends Block Kit formatted message from template' do
      stub_request(:post, webhook_url)
        .with { |req| JSON.parse(req.body)['attachments'].is_a?(Array) }
        .to_return(status: 200)

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        pr_info: pr_info,
        keywords_detected: ['session'],
        should_notify: true
      )

      result = notifier.send_slack(summary, pr_info, webhook_url)

      expect(result[:success]).to be true
    end

    it 'includes expected Block Kit structure' do
      captured_body = nil
      stub_request(:post, webhook_url)
        .with { |req| captured_body = JSON.parse(req.body); true }
        .to_return(status: 200)

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        pr_info: pr_info,
        keywords_detected: ['session'],
        should_notify: true
      )

      notifier.send_slack(summary, pr_info, webhook_url)

      expect(captured_body['attachments']).to be_an(Array)
      blocks = captured_body['attachments'][0]['blocks']
      block_types = blocks.map { |b| b['type'] }
      expect(block_types).to include('header', 'section', 'divider', 'actions')
    end

    it 'handles webhook errors gracefully' do
      stub_request(:post, webhook_url).to_return(status: 500, body: 'Error')

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        pr_info: pr_info,
        keywords_detected: [],
        should_notify: true
      )

      result = notifier.send_slack(summary, pr_info, webhook_url)

      expect(result[:success]).to be false
      expect(result[:error]).to include('500')
    end
  end

  describe '#send_teams' do
    let(:webhook_url) { 'https://outlook.office.com/webhook/test' }

    it 'sends MessageCard formatted message from template' do
      stub_request(:post, webhook_url)
        .with { |req| JSON.parse(req.body)['@type'] == 'MessageCard' }
        .to_return(status: 200)

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        pr_info: pr_info,
        keywords_detected: ['session'],
        should_notify: true
      )

      result = notifier.send_teams(summary, pr_info, webhook_url)

      expect(result[:success]).to be true
    end

    it 'includes expected MessageCard structure' do
      captured_body = nil
      stub_request(:post, webhook_url)
        .with { |req| captured_body = JSON.parse(req.body); true }
        .to_return(status: 200)

      summary = notifier.summarizer.summarize(
        detection_result: detection_result,
        pr_info: pr_info,
        keywords_detected: ['session'],
        should_notify: true
      )

      notifier.send_teams(summary, pr_info, webhook_url)

      expect(captured_body['@type']).to eq('MessageCard')
      expect(captured_body['sections']).to be_an(Array)
      expect(captured_body['potentialAction']).to be_an(Array)
    end
  end
end

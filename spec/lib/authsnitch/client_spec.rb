# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authsnitch::Client do
  subject(:client) { described_class.new(token: 'test-token') }

  describe '#initialize' do
    it 'creates an Octokit client' do
      expect(client.octokit).to be_a(Octokit::Client)
    end

    it 'enables auto pagination' do
      expect(client.octokit.auto_paginate).to be true
    end
  end

  describe '#pull_request' do
    it 'fetches PR metadata' do
      stub_request(:get, 'https://api.github.com/repos/org/repo/pulls/123')
        .to_return(
          status: 200,
          body: { number: 123, title: 'Test PR' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      pr = client.pull_request(repo: 'org/repo', pr_number: 123)

      expect(pr.number).to eq(123)
      expect(pr.title).to eq('Test PR')
    end
  end

  describe '#pull_request_diff' do
    it 'fetches PR diff with correct accept header' do
      diff_content = "diff --git a/file.rb b/file.rb\n+new line"

      stub_request(:get, 'https://api.github.com/repos/org/repo/pulls/123')
        .with(headers: { 'Accept' => 'application/vnd.github.v3.diff' })
        .to_return(status: 200, body: diff_content)

      diff = client.pull_request_diff(repo: 'org/repo', pr_number: 123)

      expect(diff).to eq(diff_content)
    end
  end

  describe '#pull_request_files' do
    it 'fetches list of changed files' do
      stub_request(:get, %r{https://api\.github\.com/repos/org/repo/pulls/123/files.*})
        .to_return(
          status: 200,
          body: [
            { filename: 'file1.rb', status: 'modified', patch: '+new' },
            { filename: 'file2.rb', status: 'added', patch: '+added' }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      files = client.pull_request_files(repo: 'org/repo', pr_number: 123)

      expect(files.length).to eq(2)
      expect(files.first.filename).to eq('file1.rb')
    end
  end

  describe '#create_pr_comment' do
    it 'posts a comment on the PR' do
      stub_request(:post, 'https://api.github.com/repos/org/repo/issues/123/comments')
        .with(body: { body: 'Test comment' }.to_json)
        .to_return(
          status: 201,
          body: { id: 1, body: 'Test comment' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      comment = client.create_pr_comment(
        repo: 'org/repo',
        pr_number: 123,
        body: 'Test comment'
      )

      expect(comment.body).to eq('Test comment')
    end
  end

  describe '.pr_context_from_env' do
    let(:event_path) { '/tmp/github_event.json' }

    before do
      allow(ENV).to receive(:fetch).with('GITHUB_EVENT_PATH', nil).and_return(event_path)
      allow(ENV).to receive(:fetch).with('GITHUB_REPOSITORY', nil).and_return('org/repo')
    end

    after do
      File.delete(event_path) if File.exist?(event_path)
    end

    it 'extracts PR context from event payload' do
      File.write(event_path, { pull_request: { number: 456 } }.to_json)

      context = described_class.pr_context_from_env

      expect(context[:repo]).to eq('org/repo')
      expect(context[:pr_number]).to eq(456)
    end

    it 'returns nil if event file does not exist' do
      allow(File).to receive(:exist?).with(event_path).and_return(false)

      expect(described_class.pr_context_from_env).to be_nil
    end

    it 'returns nil if not a PR event' do
      File.write(event_path, { action: 'push' }.to_json)

      expect(described_class.pr_context_from_env).to be_nil
    end
  end
end

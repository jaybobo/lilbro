# frozen_string_literal: true

require 'octokit'

module Lilbro
  # GitHub API client for fetching PR metadata, diffs, and changed files
  class Client
    attr_reader :octokit

    def initialize(token:)
      @octokit = Octokit::Client.new(access_token: token)
      @octokit.auto_paginate = true
    end

    # Fetch pull request metadata
    # @param repo [String] Repository in "owner/repo" format
    # @param pr_number [Integer] Pull request number
    # @return [Sawyer::Resource] PR metadata
    def pull_request(repo:, pr_number:)
      octokit.pull_request(repo, pr_number)
    end

    # Fetch the diff for a pull request
    # @param repo [String] Repository in "owner/repo" format
    # @param pr_number [Integer] Pull request number
    # @return [String] Unified diff content
    def pull_request_diff(repo:, pr_number:)
      octokit.pull_request(repo, pr_number, accept: 'application/vnd.github.v3.diff')
    end

    # Fetch list of files changed in a pull request
    # @param repo [String] Repository in "owner/repo" format
    # @param pr_number [Integer] Pull request number
    # @return [Array<Sawyer::Resource>] List of changed files with patch data
    def pull_request_files(repo:, pr_number:)
      octokit.pull_request_files(repo, pr_number)
    end

    # Post a comment on a pull request
    # @param repo [String] Repository in "owner/repo" format
    # @param pr_number [Integer] Pull request number
    # @param body [String] Comment body in markdown
    # @return [Sawyer::Resource] Created comment
    def create_pr_comment(repo:, pr_number:, body:)
      octokit.add_comment(repo, pr_number, body)
    end

    # Extract repository and PR number from GitHub Actions environment
    # @return [Hash] Contains :repo and :pr_number keys
    def self.pr_context_from_env
      event_path = ENV.fetch('GITHUB_EVENT_PATH', nil)
      return nil unless event_path && File.exist?(event_path)

      event = JSON.parse(File.read(event_path))
      pr_data = event['pull_request']
      return nil unless pr_data

      repo = ENV.fetch('GITHUB_REPOSITORY', nil)
      pr_number = pr_data['number']

      { repo: repo, pr_number: pr_number }
    end
  end
end

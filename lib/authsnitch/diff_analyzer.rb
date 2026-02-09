# frozen_string_literal: true

module Authsnitch
  # Parses unified diff format and extracts relevant change information
  class DiffAnalyzer
    # File patterns that are typically auth-sensitive
    AUTH_SENSITIVE_PATTERNS = [
      # Controllers/Routes
      /controllers?.*(?:auth|session|login|user)/i,
      /routes/i,

      # Middleware
      /middleware/i,

      # Models/Entities
      /models?.*(?:user|account|credential|token|session)/i,

      # Auth-specific directories
      /auth/i,
      /authentication/i,
      /authorization/i,

      # Configuration files
      /config.*(?:auth|oauth|saml|oidc|devise|passport)/i,
      /initializers?.*(?:auth|devise|warden|omniauth)/i,

      # Security-related
      /security/i,
      /identity/i
    ].freeze

    FileChange = Struct.new(:filename, :status, :additions, :deletions, :patch, :auth_sensitive, keyword_init: true)

    # Parse a unified diff string into structured file changes
    # @param diff [String] Unified diff content
    # @return [Array<FileChange>] Parsed file changes
    def parse(diff)
      return [] if diff.nil? || diff.empty?

      files = []
      current_file = nil
      current_additions = []
      current_deletions = []

      diff.each_line do |line|
        case line
        when /^diff --git a\/(.*) b\/(.*)/
          # Save previous file if exists
          if current_file
            files << build_file_change(current_file, current_additions, current_deletions)
          end

          current_file = Regexp.last_match(2)
          current_additions = []
          current_deletions = []
        when /^\+(?!\+\+)(.*)$/
          # Added line (exclude +++ header)
          current_additions << Regexp.last_match(1) if current_file
        when /^-(?!--)(.*)$/
          # Removed line (exclude --- header)
          current_deletions << Regexp.last_match(1) if current_file
        end
      end

      # Don't forget the last file
      if current_file
        files << build_file_change(current_file, current_additions, current_deletions)
      end

      files
    end

    # Parse files from GitHub API response (includes patch data)
    # @param files [Array<Sawyer::Resource>] Files from GitHub API
    # @return [Array<FileChange>] Parsed file changes
    def parse_files(files)
      files.map do |file|
        additions = []
        deletions = []

        if file.patch
          file.patch.each_line do |line|
            case line
            when /^\+(?!\+\+)(.*)$/
              additions << Regexp.last_match(1)
            when /^-(?!--)(.*)$/
              deletions << Regexp.last_match(1)
            end
          end
        end

        FileChange.new(
          filename: file.filename,
          status: file.status,
          additions: additions,
          deletions: deletions,
          patch: file.patch,
          auth_sensitive: auth_sensitive_file?(file.filename)
        )
      end
    end

    # Check if a filename matches auth-sensitive patterns
    # @param filename [String] File path
    # @return [Boolean]
    def auth_sensitive_file?(filename)
      AUTH_SENSITIVE_PATTERNS.any? { |pattern| filename.match?(pattern) }
    end

    # Extract only the changed content (additions and deletions) for analysis
    # @param file_changes [Array<FileChange>] Parsed file changes
    # @return [String] Combined changes formatted for analysis
    def extract_changes_for_analysis(file_changes)
      file_changes.map do |file|
        sections = []
        sections << "=== #{file.filename} ==="
        sections << "(Auth-sensitive file)" if file.auth_sensitive

        unless file.additions.empty?
          sections << "Added lines:"
          sections.concat(file.additions.map { |line| "+ #{line}" })
        end

        unless file.deletions.empty?
          sections << "Removed lines:"
          sections.concat(file.deletions.map { |line| "- #{line}" })
        end

        sections.join("\n")
      end.join("\n\n")
    end

    # Count auth-sensitive files in the changes
    # @param file_changes [Array<FileChange>] Parsed file changes
    # @return [Integer] Number of auth-sensitive files
    def count_auth_sensitive_files(file_changes)
      file_changes.count(&:auth_sensitive)
    end

    private

    def build_file_change(filename, additions, deletions)
      FileChange.new(
        filename: filename,
        status: determine_status(additions, deletions),
        additions: additions,
        deletions: deletions,
        patch: nil,
        auth_sensitive: auth_sensitive_file?(filename)
      )
    end

    def determine_status(additions, deletions)
      if additions.empty? && !deletions.empty?
        'removed'
      elsif !additions.empty? && deletions.empty?
        'added'
      else
        'modified'
      end
    end
  end
end

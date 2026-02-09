# frozen_string_literal: true

module Authsnitch
  # Formats detection results into human-readable summaries
  class Summarizer
    # Generate a comprehensive summary from detection results
    # @param detection_result [Detector::DetectionResult] Detection result from Claude
    # @param pr_info [Hash] PR metadata (title, number, author, repo, url)
    # @param keywords_detected [Array<String>] Keywords found in the diff
    # @param should_notify [Boolean] Whether notification is being sent
    # @return [Hash] Formatted summary with sections
    def summarize(detection_result:, pr_info: {}, keywords_detected: [], should_notify: false)
      {
        title: should_notify ? 'AuthSnitch - Authentication Changes Detected' : 'AuthSnitch - Review Summary',
        pr_section: build_pr_section(pr_info),
        summary: detection_result.summary,
        findings: format_findings(detection_result.findings),
        files_affected: extract_affected_files(detection_result.findings),
        keywords: keywords_detected
      }
    end

    # Generate plain text summary
    # @param summary [Hash] Summary from #summarize
    # @return [String] Plain text
    def to_text(summary)
      lines = []

      lines << summary[:title]
      lines << "=" * summary[:title].length
      lines << ""
      lines << "Summary: #{summary[:summary]}"
      lines << ""

      if summary[:findings].any?
        lines << "Findings:"
        summary[:findings].each_with_index do |finding, i|
          lines << "  #{i + 1}. #{finding[:type_display]}"
          lines << "     File: #{finding[:file]}"
          lines << "     #{finding[:description]}"
          lines << ""
        end
      end

      if summary[:files_affected].any?
        lines << "Files Affected: #{summary[:files_affected].join(', ')}"
        lines << ""
      end

      if summary[:keywords].any?
        lines << "Keywords: #{summary[:keywords].join(', ')}"
      end

      lines.join("\n")
    end

    private

    def build_pr_section(pr_info)
      {
        title: pr_info[:title] ? "##{pr_info[:number]} \"#{pr_info[:title]}\"" : nil,
        number: pr_info[:number],
        author: pr_info[:author] ? "@#{pr_info[:author]}" : nil,
        repo: pr_info[:repo],
        url: pr_info[:url]
      }
    end

    def format_findings(findings)
      findings.map do |finding|
        {
          type: finding.type,
          type_display: humanize_type(finding.type),
          file: finding.file,
          code_section: finding.code_section,
          description: finding.description
        }
      end
    end

    def humanize_type(type)
      return 'Unknown Change' unless type

      type.to_s
          .gsub('_', ' ')
          .split
          .map(&:capitalize)
          .join(' ')
    end

    def extract_affected_files(findings)
      findings.map(&:file).compact.uniq
    end

  end
end

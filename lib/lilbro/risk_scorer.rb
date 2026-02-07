# frozen_string_literal: true

require 'yaml'

module Lilbro
  # Converts Claude detection findings to a numeric risk score (0-100)
  class RiskScorer
    DEFAULTS_PATH = File.expand_path('../../config/defaults.yml', __dir__)

    # Keywords that indicate identity provider changes
    IDENTITY_PROVIDER_KEYWORDS = %w[
      okta auth0 cognito azure_ad active_directory keycloak
      ping_identity onelogin duo firebase_auth ldap saml oidc
    ].freeze

    # Keywords that indicate credential/secret handling
    CREDENTIAL_KEYWORDS = %w[
      password secret credential api_key private_key
      access_token refresh_token secret_key passwd
    ].freeze

    attr_reader :config

    def initialize(config_path: nil)
      @config = load_config(config_path)
    end

    # Calculate risk score from detection result
    # @param detection_result [Detector::DetectionResult] Detection result from Claude
    # @param file_changes [Array<DiffAnalyzer::FileChange>] Parsed file changes
    # @return [Hash] Score details with :score, :label, :color, :breakdown
    def calculate(detection_result, file_changes: [])
      return zero_score unless detection_result.auth_changes_detected

      base_score = calculate_base_score(detection_result)
      modifiers = calculate_modifiers(detection_result, file_changes)

      total_score = [base_score + modifiers[:total], 100].min

      {
        score: total_score,
        label: score_label(total_score),
        color: score_color(total_score),
        breakdown: {
          base_score: base_score,
          highest_risk: detection_result.highest_risk,
          modifiers: modifiers[:applied],
          modifier_total: modifiers[:total]
        }
      }
    end

    # Get the risk label for a score
    # @param score [Integer] Risk score (0-100)
    # @return [String] Risk label (LOW, MEDIUM, HIGH, CRITICAL)
    def score_label(score)
      labels = config['risk_labels'] || default_labels
      labels.each do |range, label|
        min, max = range.split('-').map(&:to_i)
        return label if score >= min && score <= max
      end
      'UNKNOWN'
    end

    # Get the color for a score
    # @param score [Integer] Risk score (0-100)
    # @return [String] Hex color code
    def score_color(score)
      colors = config['risk_colors'] || default_colors
      label = score_label(score).downcase
      colors[label] || '#808080'
    end

    private

    def load_config(custom_path)
      path = custom_path || DEFAULTS_PATH
      return default_config unless File.exist?(path)

      YAML.safe_load(File.read(path))
    end

    def calculate_base_score(detection_result)
      risk_scores = config['risk_scores'] || default_risk_scores

      # Start with the highest risk level found
      base = risk_scores[detection_result.highest_risk] || 0

      # Add points for each finding based on its individual risk level
      finding_scores = detection_result.findings.map do |finding|
        risk_scores[finding.risk_level] || 0
      end

      # Take the max of base score or average of findings
      if finding_scores.any?
        avg_finding_score = finding_scores.sum / finding_scores.size
        [base, avg_finding_score].max
      else
        base
      end
    end

    def calculate_modifiers(detection_result, file_changes)
      modifiers_config = config['modifiers'] || default_modifiers
      applied = []
      total = 0

      # Multiple auth-sensitive files touched
      auth_file_count = file_changes.count(&:auth_sensitive)
      if auth_file_count >= 2
        points = modifiers_config['multiple_auth_files'] || 10
        applied << { name: 'multiple_auth_files', points: points, reason: "#{auth_file_count} auth-sensitive files" }
        total += points
      end

      # Check for identity provider changes in findings
      if identity_provider_change?(detection_result)
        points = modifiers_config['identity_provider_change'] || 15
        applied << { name: 'identity_provider_change', points: points, reason: 'Identity provider modification' }
        total += points
      end

      # Check for credential handling in findings
      if credential_handling?(detection_result)
        points = modifiers_config['credential_handling'] || 20
        applied << { name: 'credential_handling', points: points, reason: 'Credential/secret handling' }
        total += points
      end

      { applied: applied, total: total }
    end

    def identity_provider_change?(detection_result)
      all_text = findings_text(detection_result)
      IDENTITY_PROVIDER_KEYWORDS.any? { |kw| all_text.include?(kw) }
    end

    def credential_handling?(detection_result)
      all_text = findings_text(detection_result)
      CREDENTIAL_KEYWORDS.any? { |kw| all_text.include?(kw) }
    end

    def findings_text(detection_result)
      text_parts = [detection_result.summary.to_s.downcase]
      detection_result.findings.each do |finding|
        text_parts << finding.type.to_s.downcase
        text_parts << finding.description.to_s.downcase
        text_parts << finding.security_relevance.to_s.downcase
      end
      text_parts.join(' ')
    end

    def zero_score
      {
        score: 0,
        label: 'NONE',
        color: '#36a64f',
        breakdown: {
          base_score: 0,
          highest_risk: 'none',
          modifiers: [],
          modifier_total: 0
        }
      }
    end

    def default_config
      {
        'risk_scores' => default_risk_scores,
        'modifiers' => default_modifiers,
        'risk_labels' => default_labels,
        'risk_colors' => default_colors
      }
    end

    def default_risk_scores
      {
        'none' => 0,
        'low' => 20,
        'medium' => 40,
        'high' => 65,
        'critical' => 85
      }
    end

    def default_modifiers
      {
        'multiple_auth_files' => 10,
        'identity_provider_change' => 15,
        'credential_handling' => 20
      }
    end

    def default_labels
      {
        '0-24' => 'LOW',
        '25-49' => 'MEDIUM',
        '50-74' => 'HIGH',
        '75-100' => 'CRITICAL'
      }
    end

    def default_colors
      {
        'low' => '#36a64f',
        'medium' => '#f2c744',
        'high' => '#ff9800',
        'critical' => '#dc3545'
      }
    end
  end
end

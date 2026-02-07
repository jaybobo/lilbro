# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Lilbro::RiskScorer do
  subject(:scorer) { described_class.new }

  let(:empty_detection_result) do
    Lilbro::Detector::DetectionResult.new(
      findings: [],
      summary: 'No auth changes detected.',
      auth_changes_detected: false,
      highest_risk: 'none',
      raw_response: nil
    )
  end

  let(:low_risk_detection_result) do
    Lilbro::Detector::DetectionResult.new(
      findings: [
        Lilbro::Detector::Finding.new(
          type: 'session_handling',
          file: 'app/controllers/sessions_controller.rb',
          code_section: 'session[:user_id] = user.id',
          description: 'Basic session assignment',
          security_relevance: 'Standard session handling',
          risk_level: 'low',
          recommendation: 'Review session configuration'
        )
      ],
      summary: 'Minor session handling changes.',
      auth_changes_detected: true,
      highest_risk: 'low',
      raw_response: nil
    )
  end

  let(:high_risk_detection_result) do
    Lilbro::Detector::DetectionResult.new(
      findings: [
        Lilbro::Detector::Finding.new(
          type: 'oauth_integration',
          file: 'lib/auth/okta_handler.rb',
          code_section: 'OktaClient.new(api_key: ENV["OKTA_KEY"])',
          description: 'New Okta integration for SSO',
          security_relevance: 'Identity provider integration affects all authentication',
          risk_level: 'high',
          recommendation: 'Security team review required'
        ),
        Lilbro::Detector::Finding.new(
          type: 'credential_storage',
          file: 'config/secrets.yml',
          code_section: 'api_secret: <%= ENV["API_SECRET"] %>',
          description: 'API secret configuration',
          security_relevance: 'Credential handling',
          risk_level: 'medium',
          recommendation: 'Verify secrets are not exposed'
        )
      ],
      summary: 'Significant authentication changes with Okta integration.',
      auth_changes_detected: true,
      highest_risk: 'high',
      raw_response: nil
    )
  end

  let(:auth_sensitive_files) do
    [
      Lilbro::DiffAnalyzer::FileChange.new(
        filename: 'app/controllers/sessions_controller.rb',
        status: 'modified',
        additions: [],
        deletions: [],
        patch: nil,
        auth_sensitive: true
      ),
      Lilbro::DiffAnalyzer::FileChange.new(
        filename: 'lib/auth/oauth_handler.rb',
        status: 'modified',
        additions: [],
        deletions: [],
        patch: nil,
        auth_sensitive: true
      )
    ]
  end

  describe '#calculate' do
    context 'when no auth changes detected' do
      it 'returns zero score' do
        result = scorer.calculate(empty_detection_result)

        expect(result[:score]).to eq(0)
        expect(result[:label]).to eq('NONE')
      end
    end

    context 'with low risk findings' do
      it 'returns low score' do
        result = scorer.calculate(low_risk_detection_result)

        expect(result[:score]).to be_between(10, 25)
        expect(result[:label]).to eq('LOW')
      end
    end

    context 'with high risk findings' do
      it 'returns high score' do
        result = scorer.calculate(high_risk_detection_result)

        expect(result[:score]).to be >= 50
        expect(%w[HIGH CRITICAL]).to include(result[:label])
      end

      it 'includes score breakdown' do
        result = scorer.calculate(high_risk_detection_result)

        expect(result[:breakdown]).to include(
          base_score: be_a(Numeric),
          highest_risk: 'high',
          modifiers: be_an(Array),
          modifier_total: be_a(Numeric)
        )
      end
    end

    context 'with modifiers' do
      it 'adds points for multiple auth-sensitive files' do
        result_without = scorer.calculate(low_risk_detection_result, file_changes: [])
        result_with = scorer.calculate(low_risk_detection_result, file_changes: auth_sensitive_files)

        expect(result_with[:score]).to be > result_without[:score]
        expect(result_with[:breakdown][:modifiers].map { |m| m[:name] }).to include('multiple_auth_files')
      end

      it 'adds points for identity provider changes' do
        result = scorer.calculate(high_risk_detection_result)
        modifier_names = result[:breakdown][:modifiers].map { |m| m[:name] }

        expect(modifier_names).to include('identity_provider_change')
      end

      it 'adds points for credential handling' do
        result = scorer.calculate(high_risk_detection_result)
        modifier_names = result[:breakdown][:modifiers].map { |m| m[:name] }

        expect(modifier_names).to include('credential_handling')
      end
    end
  end

  describe '#score_label' do
    it 'returns correct labels for score ranges' do
      expect(scorer.score_label(0)).to eq('LOW')
      expect(scorer.score_label(20)).to eq('LOW')
      expect(scorer.score_label(25)).to eq('MEDIUM')
      expect(scorer.score_label(49)).to eq('MEDIUM')
      expect(scorer.score_label(50)).to eq('HIGH')
      expect(scorer.score_label(74)).to eq('HIGH')
      expect(scorer.score_label(75)).to eq('CRITICAL')
      expect(scorer.score_label(100)).to eq('CRITICAL')
    end
  end

  describe '#score_color' do
    it 'returns correct colors for scores' do
      expect(scorer.score_color(10)).to eq('#36a64f')  # green for low
      expect(scorer.score_color(30)).to eq('#f2c744')  # yellow for medium
      expect(scorer.score_color(60)).to eq('#ff9800')  # orange for high
      expect(scorer.score_color(90)).to eq('#dc3545')  # red for critical
    end
  end
end

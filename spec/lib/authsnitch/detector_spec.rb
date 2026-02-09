# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authsnitch::Detector do
  let(:mock_client) { instance_double(Anthropic::Client) }
  let(:mock_messages) { instance_double('Messages') }

  before do
    allow(Anthropic::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:messages).and_return(mock_messages)
  end

  subject(:detector) { described_class.new(api_key: 'test-key') }

  describe '#initialize' do
    it 'loads default configuration' do
      expect(detector.config).to include('keywords')
      expect(detector.config).to include('detection_prompt')
    end

    it 'accepts custom keywords' do
      custom_detector = described_class.new(
        api_key: 'test-key',
        custom_keywords: 'custom_auth,my_sso'
      )

      expect(custom_detector.all_keywords).to include('custom_auth')
      expect(custom_detector.all_keywords).to include('my_sso')
    end
  end

  describe '#all_keywords' do
    it 'includes authentication methods' do
      keywords = detector.all_keywords

      expect(keywords).to include('jwt')
      expect(keywords).to include('oauth')
      expect(keywords).to include('saml')
    end

    it 'includes identity providers' do
      keywords = detector.all_keywords

      expect(keywords).to include('okta')
      expect(keywords).to include('auth0')
      expect(keywords).to include('cognito')
    end

    it 'includes sensitive patterns' do
      keywords = detector.all_keywords

      expect(keywords).to include('password')
      expect(keywords).to include('api_key')
      expect(keywords).to include('secret')
    end
  end

  describe '#analyze' do
    context 'with empty input' do
      it 'returns empty result for nil' do
        result = detector.analyze(nil)

        expect(result.auth_changes_detected).to be false
        expect(result.findings).to be_empty
      end

      it 'returns empty result for empty string' do
        result = detector.analyze('')

        expect(result.auth_changes_detected).to be false
        expect(result.findings).to be_empty
      end
    end

    context 'with valid diff content' do
      let(:diff_content) do
        <<~DIFF
          === app/controllers/sessions_controller.rb ===
          (Auth-sensitive file)
          Added lines:
          + def create
          +   token = JWT.encode(payload, secret)
          +   session[:access_token] = token
          + end
        DIFF
      end

      let(:claude_response) do
        {
          'findings' => [
            {
              'type' => 'jwt_implementation',
              'file' => 'app/controllers/sessions_controller.rb',
              'code_section' => 'JWT.encode(payload, secret)',
              'description' => 'JWT token generation',
              'security_relevance' => 'Token creation affects authentication',
              'risk_level' => 'medium',
              'recommendation' => 'Verify token expiry is set'
            }
          ],
          'summary' => 'JWT token handling changes detected.',
          'auth_changes_detected' => true,
          'highest_risk' => 'medium'
        }.to_json
      end

      before do
        response_content = double('ContentBlock', text: claude_response)
        response = double('Response', content: [response_content])
        allow(mock_messages).to receive(:create).and_return(response)
      end

      it 'returns structured detection result' do
        result = detector.analyze(diff_content)

        expect(result).to be_a(Authsnitch::Detector::DetectionResult)
        expect(result.auth_changes_detected).to be true
        expect(result.highest_risk).to eq('medium')
      end

      it 'parses findings correctly' do
        result = detector.analyze(diff_content)

        expect(result.findings.length).to eq(1)

        finding = result.findings.first
        expect(finding.type).to eq('jwt_implementation')
        expect(finding.risk_level).to eq('medium')
      end
    end
  end
end

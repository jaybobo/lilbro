# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Lilbro::DiffAnalyzer do
  subject(:analyzer) { described_class.new }

  describe '#parse' do
    let(:sample_diff) do
      <<~DIFF
        diff --git a/app/controllers/sessions_controller.rb b/app/controllers/sessions_controller.rb
        index abc123..def456 100644
        --- a/app/controllers/sessions_controller.rb
        +++ b/app/controllers/sessions_controller.rb
        @@ -10,6 +10,10 @@ class SessionsController < ApplicationController
           def create
        +    # New OAuth logic
        +    token = auth_service.generate_token(user)
        +    session[:access_token] = token
        -    redirect_to root_path
        +    redirect_to dashboard_path
           end
         end
        diff --git a/lib/auth/oauth_handler.rb b/lib/auth/oauth_handler.rb
        new file mode 100644
        index 0000000..abc123
        --- /dev/null
        +++ b/lib/auth/oauth_handler.rb
        @@ -0,0 +1,15 @@
        +class OAuthHandler
        +  def authenticate(code)
        +    # Handle OAuth callback
        +  end
        +end
      DIFF
    end

    it 'parses files from unified diff' do
      result = analyzer.parse(sample_diff)

      expect(result.length).to eq(2)
      expect(result.map(&:filename)).to contain_exactly(
        'app/controllers/sessions_controller.rb',
        'lib/auth/oauth_handler.rb'
      )
    end

    it 'extracts added lines' do
      result = analyzer.parse(sample_diff)
      sessions_file = result.find { |f| f.filename.include?('sessions_controller') }

      expect(sessions_file.additions).to include('    # New OAuth logic')
      expect(sessions_file.additions).to include('    token = auth_service.generate_token(user)')
    end

    it 'extracts removed lines' do
      result = analyzer.parse(sample_diff)
      sessions_file = result.find { |f| f.filename.include?('sessions_controller') }

      expect(sessions_file.deletions).to include('    redirect_to root_path')
    end

    it 'identifies auth-sensitive files' do
      result = analyzer.parse(sample_diff)

      expect(result.all?(&:auth_sensitive)).to be true
    end

    it 'returns empty array for nil input' do
      expect(analyzer.parse(nil)).to eq([])
    end

    it 'returns empty array for empty string' do
      expect(analyzer.parse('')).to eq([])
    end
  end

  describe '#auth_sensitive_file?' do
    it 'detects controllers with auth keywords' do
      expect(analyzer.auth_sensitive_file?('app/controllers/sessions_controller.rb')).to be true
      expect(analyzer.auth_sensitive_file?('app/controllers/auth_controller.rb')).to be true
      expect(analyzer.auth_sensitive_file?('app/controllers/login_controller.rb')).to be true
    end

    it 'detects middleware files' do
      expect(analyzer.auth_sensitive_file?('app/middleware/authentication.rb')).to be true
    end

    it 'detects auth configuration files' do
      expect(analyzer.auth_sensitive_file?('config/initializers/devise.rb')).to be true
      expect(analyzer.auth_sensitive_file?('config/oauth.yml')).to be true
    end

    it 'detects auth-specific directories' do
      expect(analyzer.auth_sensitive_file?('lib/auth/token_handler.rb')).to be true
      expect(analyzer.auth_sensitive_file?('app/services/authentication_service.rb')).to be true
    end

    it 'does not flag unrelated files' do
      expect(analyzer.auth_sensitive_file?('app/controllers/products_controller.rb')).to be false
      expect(analyzer.auth_sensitive_file?('lib/utils/string_helper.rb')).to be false
      expect(analyzer.auth_sensitive_file?('README.md')).to be false
    end
  end

  describe '#extract_changes_for_analysis' do
    let(:file_changes) do
      [
        Lilbro::DiffAnalyzer::FileChange.new(
          filename: 'app/controllers/auth_controller.rb',
          status: 'modified',
          additions: ['def login', '  authenticate_user!', 'end'],
          deletions: ['def old_login'],
          patch: nil,
          auth_sensitive: true
        ),
        Lilbro::DiffAnalyzer::FileChange.new(
          filename: 'lib/helpers.rb',
          status: 'modified',
          additions: ['def format_date'],
          deletions: [],
          patch: nil,
          auth_sensitive: false
        )
      ]
    end

    it 'formats changes for analysis' do
      result = analyzer.extract_changes_for_analysis(file_changes)

      expect(result).to include('=== app/controllers/auth_controller.rb ===')
      expect(result).to include('(Auth-sensitive file)')
      expect(result).to include('+ def login')
      expect(result).to include('- def old_login')
    end

    it 'includes non-sensitive files without the auth label' do
      result = analyzer.extract_changes_for_analysis(file_changes)

      expect(result).to include('=== lib/helpers.rb ===')
      expect(result.scan('(Auth-sensitive file)').length).to eq(1)
    end
  end

  describe '#count_auth_sensitive_files' do
    it 'counts auth-sensitive files correctly' do
      file_changes = [
        Lilbro::DiffAnalyzer::FileChange.new(filename: 'a.rb', status: 'modified', additions: [], deletions: [], patch: nil, auth_sensitive: true),
        Lilbro::DiffAnalyzer::FileChange.new(filename: 'b.rb', status: 'modified', additions: [], deletions: [], patch: nil, auth_sensitive: false),
        Lilbro::DiffAnalyzer::FileChange.new(filename: 'c.rb', status: 'modified', additions: [], deletions: [], patch: nil, auth_sensitive: true)
      ]

      expect(analyzer.count_auth_sensitive_files(file_changes)).to eq(2)
    end
  end
end

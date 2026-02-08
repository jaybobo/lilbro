# LilBro - Authentication Change Detection GitHub Action

Misconfigured authentication and sensitive data leaks? **Nobody got time for that!**

LilBro is a lovable tattletale that helps understaffed appsec teams monitor pull requests for authentication-related changes and alerts security teams when an additional manual or AI-powered security review may be needed.

## Features

- **Claude-Powered Detection**: Uses Claude AI to intelligently analyze code changes for authentication-related modifications
- **Configurable Keywords**: Detect JWT, OAuth, SAML, SSO, MFA, and identity provider integrations (Okta, Auth0, Azure AD, etc.)
- **Risk Scoring**: Automatically calculates risk scores (0-100) based on the nature and scope of changes
- **Multi-Channel Notifications**: Alert via PR comments, Slack, and/or Microsoft Teams
- **Customizable Prompts**: Override detection prompts for organization-specific requirements
- **Advisory Only**: Never blocks merges - provides visibility without friction

## Quick Start

```yaml
name: Authentication Review Check
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  auth-check:
    runs-on: ubuntu-latest
    steps:
      - uses: your-org/lilbro@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          post_pr_comment: true
          slack_webhook_url: ${{ secrets.SLACK_SECURITY_WEBHOOK }}
```

## Configuration

### Required Inputs

| Input | Description |
|-------|-------------|
| `github_token` | GitHub token for API access (usually `${{ secrets.GITHUB_TOKEN }}`) |
| `anthropic_api_key` | Claude API key for detection and summarization |

### Notification Channels

| Input | Description | Default |
|-------|-------------|---------|
| `post_pr_comment` | Post findings as a PR comment | `false` |
| `slack_webhook_url` | Slack incoming webhook URL | - |
| `teams_webhook_url` | Microsoft Teams webhook URL | - |

### Thresholds

Each notification channel can have its own threshold, enabling scenarios like:
- PR comments at score 30+ (developer visibility)
- Slack at score 50+ (security team awareness)
- Teams at score 75+ (critical alerts only)

| Input | Description | Default |
|-------|-------------|---------|
| `risk_threshold` | Minimum score to trigger any notification | `50` |
| `pr_comment_threshold` | Minimum score for PR comment | Uses `risk_threshold` |
| `slack_threshold` | Minimum score for Slack | Uses `risk_threshold` |
| `teams_threshold` | Minimum score for Teams | Uses `risk_threshold` |

### Customization

| Input | Description |
|-------|-------------|
| `custom_keywords` | Additional keywords to detect (comma-separated) |
| `detection_prompt` | Custom detection prompt (overrides default) |
| `detection_config_path` | Path to custom `detection.yml` in repo |

## Risk Scoring

LilBro calculates risk scores based on Claude's analysis:

| Risk Level | Score Range |
|------------|-------------|
| None | 0 |
| Low | 10-24 |
| Medium | 25-49 |
| High | 50-74 |
| Critical | 75-100 |

### Score Modifiers

Additional points are added for:
- **Multiple auth-sensitive files touched**: +10
- **Identity provider changes** (Okta, Azure AD, etc.): +15
- **Credential/secret handling**: +20

## Keywords Detected

### Authentication Methods
`jwt`, `oauth`, `saml`, `sso`, `oidc`, `bearer`, `basic-auth`, `kerberos`, `mtls`

### Identity Providers
`okta`, `auth0`, `cognito`, `azure_ad`, `active_directory`, `keycloak`, `ping_identity`

### Sensitive Patterns
`password`, `secret`, `credential`, `api_key`, `access_token`, `refresh_token`, `session`

### Auth Operations
`login`, `logout`, `authenticate`, `authorize`, `mfa`, `2fa`, `totp`, `webauthn`

### Framework Support (Built-in)

| Language | Frameworks |
|----------|------------|
| **Ruby** | `devise`, `doorkeeper`, `warden`, `omniauth` |
| **JavaScript** | `passport`, `auth.js`, `next-auth`, `express-session` |
| **Python** | `django-allauth`, `flask-login`, `fastapi-users` |

## Custom Configuration

Create a `.github/lilbro/detection.yml` file in your repository:

```yaml
# Add organization-specific keywords
keywords:
  internal_auth:
    - internal_sso
    - corp_auth
    - my_company_oauth

# Custom detection prompt (optional)
detection_prompt: |
  You are reviewing code for the application security team.
  Identify if any authentication related changes are being made.

  Keywords to watch for: {keywords}

  [Include your custom instructions here]
```

Then reference it in your workflow:

### Language-Specific Framework Examples

Add these framework-specific keywords to your `detection.yml` based on your stack:

```yaml
# .github/lilbro/detection.yml
keywords:
  # Ruby frameworks
  ruby_frameworks:
    - devise
    - doorkeeper
    - warden
    - omniauth

  # JavaScript frameworks
  javascript_frameworks:
    - passport
    - auth.js
    - next-auth

  # Python frameworks
  python_frameworks:
    - django-allauth
    - flask-login
    - fastapi-users

  # Organization-specific
  internal_auth:
    - corp_sso
    - internal_oauth
```

## Example Workflow

```yaml
name: Security Review Check
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  auth-check:
    runs-on: ubuntu-latest
    steps:
      - uses: your-org/lilbro@v1
        with:
          # Required
          github_token: ${{ secrets.GITHUB_TOKEN }}
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}

          # Enable all notification channels with different thresholds
          post_pr_comment: true
          pr_comment_threshold: 30

          slack_webhook_url: ${{ secrets.SLACK_SECURITY_WEBHOOK }}
          slack_threshold: 50

          teams_webhook_url: ${{ secrets.TEAMS_SECURITY_WEBHOOK }}
          teams_threshold: 75

          # Add custom keywords
          custom_keywords: 'internal_sso,corp_ldap,my_auth_service'

          # Use custom config from repo
          detection_config_path: .github/lilbro/detection.yml
```

## Outputs

The action provides the following outputs:

| Output | Description |
|--------|-------------|
| `risk_score` | Calculated risk score (0-100) |
| `risk_label` | Risk label (LOW, MEDIUM, HIGH, CRITICAL) |
| `auth_changes_detected` | Whether auth changes were found (true/false) |
| `findings_count` | Number of findings detected |
| `summary` | Brief summary of the analysis |

Use outputs in subsequent steps:

```yaml
- uses: your-org/lilbro@v1
  id: security-check
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}

- name: Check results
  run: |
    echo "Risk Score: ${{ steps.security-check.outputs.risk_score }}"
    echo "Findings: ${{ steps.security-check.outputs.findings_count }}"
```

## Notification Format

### PR Comment Example

```markdown
## LilBro Security Alert - HIGH RISK

**Risk Score: 72 (HIGH)** [*******---]

**PR:** #123 "Add OAuth login flow"
**Author:** @developer

### Summary
OAuth integration changes detected with new token handling.

### Findings

#### Oauth Integration
**File:** `lib/auth/oauth_handler.rb`
**Risk:** `HIGH`

New OAuth token validation logic

> **Why this matters:** Token handling affects authentication security

**Recommendation:** Review token validation and expiry logic
```

### Slack/Teams Rich Card

The action sends rich cards with:
- Risk score visualization
- PR metadata
- Summary of changes
- Affected files list
- Detected keywords
- Links to view PR and diff

## Development

### Prerequisites

- Ruby 3.2+
- Bundler

### Setup

```bash
bundle install
```

### Running Tests

```bash
bundle exec rspec
```

### Local Testing with act

Use [act](https://github.com/nektos/act) to run the action locally.

**1. Create `.secrets`** with your API keys:

```bash
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxx
SLACK_SECURITY_WEBHOOK=https://hooks.slack.com/services/xxx/xxx/xxx
```

**2. Create `test-event.json`** to simulate a pull request event:

```json
{
  "pull_request": {
    "number": 123,
    "title": "Add OAuth login flow",
    "html_url": "https://github.com/your-org/your-repo/pull/123",
    "user": {
      "login": "developer"
    }
  },
  "repository": {
    "full_name": "your-org/your-repo"
  }
}
```

**3. Run act:**

```bash
act pull_request -e test-event.json --secret-file .secrets
```

> **Note:** Ensure `.secrets` is in your `.gitignore` to avoid committing credentials.

## Architecture

```
lilbro/
├── action.yml              # GitHub Action metadata
├── Dockerfile              # Ruby 3.2 container
├── Gemfile                 # Dependencies
├── entrypoint.rb           # Main entry point
├── lib/
│   └── lilbro/
│       ├── client.rb       # GitHub API client (octokit)
│       ├── diff_analyzer.rb # Parse PR diffs
│       ├── detector.rb     # Claude-powered detection
│       ├── risk_scorer.rb  # Convert findings to scores
│       ├── summarizer.rb   # Format detection results
│       └── notifier.rb     # Slack/Teams/PR webhooks
├── config/
│   ├── detection.yml       # Keywords + detection prompt
│   └── defaults.yml        # Default thresholds & settings
└── spec/                   # RSpec tests
```

## Contributing

Additions, edits and suggestions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for recommended guidelines.

## License

MIT

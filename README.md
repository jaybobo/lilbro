# AuthSnitch

## What's AuthSnitch?

AuthSnitch is an authentication change detection GitHub Action.

Misconfigured authentication and sensitive data leaks? **Nobody got time for that!**

It is a lovable tattletale that helps understaffed appsec teams monitor pull requests for authentication-related changes and alerts when an additional manual or AI-powered security review may be needed.

## Features

- **Claude-Powered Detection**: Uses Claude AI to intelligently analyze code changes for authentication-related modifications
- **Configurable Keywords**: Detect JWT, OAuth, SAML, SSO, MFA, and identity provider integrations (Okta, Auth0, Azure AD, etc.)
- **Boolean Signal Notifications**: Two independent signals (Claude analysis + keyword matching) determine whether to notify — no numeric scores or thresholds
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
      - uses: jaybobo/authsnitch@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          post_pr_comment: true
          slack_webhook_url: ${{ secrets.SLACK_SECURITY_WEBHOOK }}
```

### Using Latest Commit

To use the latest commit from main (includes recent fixes not yet in a release):

```yaml
      - uses: jaybobo/authsnitch@main
```

Or pin to a specific commit SHA for stability:

```yaml
      - uses: jaybobo/authsnitch@abc1234
```

## Configuration

### Required Inputs

| Input | Description |
|-------|-------------|
| `github_token` | GitHub token for API access (usually `${{ secrets.GITHUB_TOKEN }}`) |
| `anthropic_api_key` | Claude API key for detection and summarization |

### Notification Channels
Instructions for enabling incoming webhooks for [Microsoft Teams](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook?tabs=classicteams%2Cdotnet) and [Slack](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/).

| Input | Description | Default |
|-------|-------------|---------|
| `post_pr_comment` | Post findings as a PR comment | `false` |
| `slack_webhook_url` | Slack incoming webhook URL | - |
| `teams_webhook_url` | Microsoft Teams webhook URL | - |

### Signal Configuration

| Input | Description | Default |
|-------|-------------|---------|
| `notify_on_claude_only` | Notify when only Claude detects auth changes but no keywords match | `false` |
| `notify_on_keywords_only` | Notify when only keywords match but Claude does not detect auth changes | `false` |

### Customization

| Input | Description |
|-------|-------------|
| `custom_keywords` | Additional keywords to detect (comma-separated) |
| `detection_prompt` | Custom detection prompt (overrides default) |
| `detection_config_path` | Path to custom `detection.yml` in repo |

## Notification Logic

AuthSnitch uses two boolean signals to decide whether to send notifications:

1. **Claude signal** — Did Claude's analysis detect authentication changes?
2. **Keyword signal** — Were any keywords from `detection.yml` found in the diff?

| Claude | Keywords | Default Action | Configurable? |
|--------|----------|---------------|---------------|
| Yes    | Yes      | Notify        | No (always)   |
| Yes    | No       | Skip          | Yes — `notify_on_claude_only: true` |
| No     | Yes      | Skip          | Yes — `notify_on_keywords_only: true` |
| No     | No       | Skip          | No (never)    |

By default, notifications are only sent when **both** signals agree. You can enable either `notify_on_claude_only` or `notify_on_keywords_only` to cast a wider net.

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

Create a `.github/authsnitch/detection.yml` file in your repository:

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
# .github/authsnitch/detection.yml
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
      - uses: jaybobo/authsnitch@v1
        with:
          # Required
          github_token: ${{ secrets.GITHUB_TOKEN }}
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}

          # Enable notification channels
          post_pr_comment: true
          slack_webhook_url: ${{ secrets.SLACK_SECURITY_WEBHOOK }}
          teams_webhook_url: ${{ secrets.TEAMS_SECURITY_WEBHOOK }}

          # Widen the notification net (optional)
          notify_on_claude_only: true
          notify_on_keywords_only: false

          # Add custom keywords
          custom_keywords: 'internal_sso,corp_ldap,my_auth_service'

          # Use custom config from repo
          detection_config_path: .github/authsnitch/detection.yml
```

## Outputs

The action provides the following outputs:

| Output | Description |
|--------|-------------|
| `auth_changes_detected` | Whether Claude detected auth changes (true/false) |
| `findings_count` | Number of findings detected |
| `summary` | Brief summary of the analysis |
| `keywords_matched` | Comma-separated list of matched keywords |

Use outputs in subsequent steps:

```yaml
- uses: jaybobo/authsnitch@v1
  id: security-check
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}

- name: Check results
  run: |
    echo "Auth changes: ${{ steps.security-check.outputs.auth_changes_detected }}"
    echo "Findings: ${{ steps.security-check.outputs.findings_count }}"
    echo "Keywords: ${{ steps.security-check.outputs.keywords_matched }}"
```

## Custom Templates

Notification layouts are rendered from ERB templates in `config/templates/`. You can edit these files directly to customize the notification format for your organization.

### Default Templates

| Template | Channel | Format |
|----------|---------|--------|
| `github_pr_comment.md.erb` | GitHub PR comment | Markdown |
| `slack.json.erb` | Slack webhook | Block Kit JSON |
| `teams.json.erb` | Teams webhook | MessageCard JSON |

### Template Variables

All templates receive two variables:

- **`summary`** — Hash with keys: `title`, `pr_section`, `summary`, `findings`, `files_affected`, `keywords`
- **`pr_info`** — Hash with keys: `title`, `number`, `author`, `repo`, `url`

A `truncate(text, max)` helper method is also available in all templates.

### Customizing Templates

Edit the ERB files in `config/templates/` to change notification layouts. For example, to add a custom footer to PR comments:

```erb
<%# config/templates/github_pr_comment.md.erb %>
## <%= summary[:title] %>
...
---
*Reviewed by YourCompany Security Team*
```

## Notification Format

### PR Comment Example

```markdown
## AuthSnitch - Authentication Changes Detected

### Summary
OAuth integration changes detected with new token handling.

### Findings

#### Oauth Integration
**File:** `lib/auth/oauth_handler.rb`
**Code:** `def authenticate(token)`

New OAuth token validation logic
```

### Slack/Teams Rich Card

The action sends rich cards with:
- Signal summary (Claude: Detected, Keywords: oauth, jwt)
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
authsnitch/
├── action.yml              # GitHub Action metadata
├── Dockerfile              # Ruby 3.2 container
├── Gemfile                 # Dependencies
├── entrypoint.rb           # Main entry point
├── lib/
│   └── authsnitch/
│       ├── client.rb       # GitHub API client (octokit)
│       ├── diff_analyzer.rb # Parse PR diffs
│       ├── detector.rb     # Claude-powered detection
│       ├── summarizer.rb   # Format detection results
│       └── notifier.rb     # Slack/Teams/PR webhooks
├── config/
│   ├── detection.yml       # Keywords + detection prompt
│   ├── defaults.yml        # Default settings
│   └── templates/          # Editable ERB notification templates
│       ├── github_pr_comment.md.erb
│       ├── slack.json.erb
│       └── teams.json.erb
└── spec/                   # RSpec tests
```

## Contributing

Additions, edits and suggestions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for recommended guidelines.

## License

MIT

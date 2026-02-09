# AuthSnitch v0.1.0-alpha

> Your lovable tattletale for authentication change detection

This is the initial alpha release of AuthSnitch, a GitHub Action that monitors pull requests for authentication-related changes and alerts security teams when manual review may be needed.

## Features

- **Claude-Powered Detection** - AI-driven analysis of code diffs for auth-related changes
- **Comprehensive Keyword Detection** - JWT, OAuth, SAML, SSO, MFA, identity providers, and more
- **Framework Support** - Built-in detection for popular auth frameworks:
  - Ruby: Devise, Doorkeeper, Warden, OmniAuth
  - JavaScript: Passport.js, Auth.js, NextAuth
  - Python: django-allauth, Flask-Login, FastAPI-Users
- **Risk Scoring** - Automatic 0-100 risk scores with modifiers for sensitive changes
- **Multi-Channel Notifications** - PR comments, Slack, and Microsoft Teams
- **Customizable** - Override keywords and detection prompts for your organization
- **Advisory Only** - Never blocks merges, just provides visibility

## Installation

```yaml
# .github/workflows/authsnitch.yml
name: Authentication Review Check
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  auth-check:
    runs-on: ubuntu-latest
    steps:
      - uses: your-org/authsnitch@v0.1.0-alpha
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          post_pr_comment: true
```

## Requirements

- Anthropic API key (Claude access)
- GitHub token (provided automatically via `secrets.GITHUB_TOKEN`)

## Known Limitations

- Alpha release - APIs and configuration format may change
- Large diffs may be truncated before analysis
- Rate limits apply based on your Anthropic API plan

## What's Next

- [ ] Support for custom file pattern exclusions
- [ ] Caching for repeat analysis
- [ ] Additional notification channels (email, PagerDuty)
- [ ] Baseline/ignore list for known patterns

## Feedback

This is an alpha release. Please report issues and share feedback:
- [Open an issue](https://github.com/jaybobo/authsnitch/issues)

---

**Full Changelog**: https://github.com/jaybobo/authsnitch/commits/v0.1.0-alpha

# Contributing to AuthSnitch

Thanks for your interest in contributing to AuthSnitch!

## Development Setup

```bash
# Clone the repo
git clone https://github.com/your-org/authsnitch.git
cd authsnitch

# Install dependencies (requires Ruby 3.2+)
bundle install

# Run tests
bundle exec rspec
```

## Making Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`bundle exec rspec`)
6. Commit your changes
7. Push to your fork and open a Pull Request

## Code Style

- Follow existing code patterns
- Use meaningful variable and method names
- Keep methods small and focused
- Add comments only where logic isn't self-evident

## Adding New Keywords

To add detection keywords, edit `config/detection.yml`:

```yaml
keywords:
  your_category:
    - keyword1
    - keyword2
```

## Testing

- All new features should include tests
- Run the full test suite before submitting a PR
- Use VCR cassettes for external API mocking

## Reporting Issues

When reporting bugs, please include:
- Ruby version (`ruby -v`)
- Steps to reproduce
- Expected vs actual behavior

## Questions?

Open an issue for discussion before starting large changes.

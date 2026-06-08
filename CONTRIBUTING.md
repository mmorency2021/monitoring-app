# Contributing to Rootless Monitor Agent

Thank you for your interest in contributing! This project demonstrates rootless monitoring for Kubernetes security compliance.

## How to Contribute

### Reporting Issues
- Use GitHub Issues to report bugs or suggest features
- Include Kubernetes version, container runtime, and kernel version
- Provide relevant logs and manifests

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly (see TESTING.md)
5. Commit with clear messages (`git commit -m 'Add amazing feature'`)
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Guidelines

#### Security First
- Never introduce root requirements
- Maintain Pod Security Standards (Restricted tier) compliance
- Document any capability additions with justification

#### Code Style
- Python: Follow PEP 8
- YAML: 2-space indentation
- Comments: Explain WHY, not WHAT

#### Testing
- Test all three variants (minimal, enhanced, eBPF)
- Verify on multiple Kubernetes versions
- Ensure security restrictions work

#### Documentation
- Update README.md for feature changes
- Add examples to TESTING.md
- Document security implications

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/monitoring-app.git
cd monitoring-app

# Build and test
docker build -t rootless-monitor:dev .
./deploy.sh minimal

# Run tests
oc rsh -n rootless-monitor $(oc get pod -n rootless-monitor -l app=rootless-monitor -o jsonpath='{.items[0].metadata.name}') id
```

## Release Process

1. Update version in manifests
2. Update CHANGELOG.md
3. Tag release: `git tag -a v1.0.0 -m "Release v1.0.0"`
4. Push tag: `git push origin v1.0.0`

## Questions?

Open a GitHub Discussion or Issue!

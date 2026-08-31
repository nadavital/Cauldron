# Security

## Report a vulnerability privately

Use [GitHub's private vulnerability reporting form](https://github.com/nadavital/Cauldron/security/advisories/new). Do not put credentials, personal recipes, account records, or exploit details in a public issue.

Include the affected app version or website URL, reproduction steps using your own account, and the expected impact. Redact sensitive material. Do not access other users' data, disrupt the service, or conduct load tests against production.

Maintainer availability is limited; no response-time or patch-delivery guarantee is offered. Reports should target the latest released app or current production website; older releases may not receive separate fixes.

## Repository safeguards

- GitHub secret scanning, push protection, Dependabot alerts, and private reports are enabled.
- CI scans reachable Git history with Gitleaks and analyzes the JavaScript/TypeScript backend with CodeQL. Neither replaces manual review or native-app security testing.
- The Gitleaks ignore file lists two exact historical false-positive fingerprints, not whole directories or credential types. Do not add real credentials to it.
- Dependency PRs do not automatically merge or deploy. Review compatibility, run the existing tests, and deploy through the documented release process.
- Production secrets belong in the provider's secret store, not Git, CI output, screenshots, or issue attachments. Repository workflows must not receive production CloudKit or Firebase signing keys.

If a real credential is exposed, revoke or rotate it first. Deleting a file from the current branch does not remove Git history, forks, or cached copies. Coordinate any history rewrite with maintainers.

Firebase client API keys and public CloudKit/app identifiers are not admin credentials. Their visibility does not replace backend authorization, ownership checks, API restrictions, or privacy validation.

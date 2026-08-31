# Cauldron

A recipe book for iPhone, iPad, and Mac, made by [Nadav Avital](https://www.nadavavital.com/).

[Browse recipes](https://cauldronrecipes.com/) · [App Store](https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943) · [Support](https://www.nadavavital.com/apps/support/?app=Cauldron)

## Maintenance

Development availability is limited. This repository remains public for transparency; it is not a promise of ongoing feature development or immediate support. Security reports are welcome through the private channel in [SECURITY.md](SECURITY.md). Automated dependency updates require review and are not automatically merged or deployed.

## Architecture and development

The native SwiftUI app uses CloudKit for content and synchronization. Firebase hosts the public recipe website and a replaceable publication index; it is not the authority for private recipe content. See [AGENTS.md](AGENTS.md) for build commands, tests, architecture constraints, and release safeguards.

Local builds require your own Apple signing configuration and backend credentials where applicable. Never commit private keys, provisioning credentials, service-account JSON, `.env` files, or production data. Public app identifiers are not authorization credentials.

The empty legacy SwiftData store in `CauldronTests/Fixtures` is an intentional migration-test fixture. Do not remove it as generated data.

## Licensing

No open-source license has been granted for the project. Public visibility does not itself grant permission to redistribute the app, branding, or assets. Third-party components retain their respective licenses. Contact the author for other uses.

# Security Policy

## Supported Versions

Security fixes are made for the latest published release. Older builds should be upgraded before a report is evaluated.

## Reporting a Vulnerability

Use the repository's private vulnerability reporting feature under **Security > Report a vulnerability** when it is available. If the repository host does not expose private vulnerability reporting, contact the publisher privately through the same channel where the app was distributed.

Do not disclose a suspected vulnerability in a public issue. Include the affected app version and build, macOS version, impact, minimal reproduction steps, and whether the issue reproduces with synthetic data.

Never attach raw Codex JSONL logs, authentication files, credentials, exported usage history, or screenshots containing personal project and chat names. Use `make demo-data` to create a safe reproduction fixture.

Reports should avoid accessing data that is not yours, disrupting services, or transmitting another person's data. A coordinated disclosure timeline should be agreed upon before public discussion.

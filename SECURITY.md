# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository. Do not open a public issue for a vulnerability that could put users at risk.

Include the affected installer, a description of the impact and enough information to reproduce the issue safely.

## Trust model

Official installers are distributed only from `https://get.tegramc.com`.

The scripts in this repository are intentionally public so users can review what runs on their machines. The SteamOS installer does not require root access, does not collect telemetry and restricts application downloads to Tegra's official CDN.

Checksums protect downloads from corruption. They do not replace HTTPS or a signed release manifest. Manifest signing may be added in the future as the distribution pipeline evolves.

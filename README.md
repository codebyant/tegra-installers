# Tegra installers

Official, auditable installation scripts for [Tegra](https://tegramc.com).

The launcher itself lives in a separate repository. This repository contains only the small scripts used to install Tegra on supported operating systems.

## Available installers

| Platform | Status | Source |
| --- | --- | --- |
| SteamOS, Steam Deck and Steam Machine | Available | [`installers/steamos/install.sh`](installers/steamos/install.sh) |
| Generic Linux | Planned | Not available yet |
| macOS | Planned | Not available yet |
| Windows | Planned | Not available yet |

## SteamOS

Quick installation:

```bash
curl -fsSL https://install.tegramc.com/install-steamos.sh | bash
```

Review before running:

```bash
curl -fsSLo install-tegra.sh https://install.tegramc.com/install-steamos.sh
less install-tegra.sh
bash install-tegra.sh
```

The SteamOS installer:

- does not require `sudo`;
- installs the Tegra AppImage inside the current user's data directory;
- verifies the AppImage SHA-512 checksum before installing it;
- accepts downloads only from Tegra's official CDN;
- creates the desktop entry and registers the `tegra:` protocol;
- adds Tegra to the Steam library using SteamOS's own helper;
- does not collect or send installation telemetry.

## Repository structure

```text
installers/
  steamos/       Current SteamOS installer
  linux/         Future generic Linux installers
  macos/         Future macOS installers
  windows/       Future Windows installers
tests/           Installer integration tests
public/          Static landing page
```

Each future installer should have its own directory, documentation and tests. Platform-specific scripts must not contain credentials, private endpoints or launcher source code.

## Distribution

The repository is deployed as a static Railway service. `install.tegramc.com` points to that service, and Railway's CDN can cache the public files at the edge.

Railway deploys directly from the default branch. Pull requests run the tests before changes are merged. The official domain remains the canonical installation address; GitHub is the public source and review interface.

## Development

Requirements:

- Node.js 22 or newer
- Bash
- Docker, for validating the production image

Run the SteamOS integration test:

```bash
node tests/steamos-installer.mjs
```

Build the production container:

```bash
docker build -t tegra-installers .
```

## Security

Please read [SECURITY.md](SECURITY.md) before reporting a vulnerability. Never run a Tegra installer from a domain you do not recognize.

## License

The installation scripts and supporting files in this repository are licensed under the [MIT License](LICENSE).

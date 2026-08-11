# scripts

This repository holds small helper shell scripts used to automate admin and maintenance tasks.

Each script in the repository has its own document in the docs/ folder with usage instructions, prerequisites, examples and safety notes. Use the per-script documents for details; the list below gives a high-level summary of available scripts.

Available scripts
- delete-tailscale-machines.sh — Bulk-delete Tailscale machines by name or tag. See docs/delete-tailscale-machines.md for usage and examples.

Contributing
- Add new scripts to the repository as executable shell files.
- Add a matching docs/<script-name>.md with usage, flags, examples, and any prerequisites.
- Open a pull request with your changes; list any required credentials or secrets that are not committed to the repo.

License
This repository is covered under the LICENSE file at the repository root.

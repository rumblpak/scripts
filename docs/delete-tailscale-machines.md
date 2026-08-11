# delete-tailscale-machines.sh

Purpose
- Bulk-delete machines from a Tailscale account by matching names or tags. Useful for cleaning up stale or test machines that are no longer needed.

Prerequisites
- jq installed (for JSON parsing).
- curl installed.
- A valid Tailscale API key with permissions to list and delete devices. Do NOT commit the API key into the repository.

Synopsis
- Basic usage:
  ./delete-tailscale-machines.sh [options] <filter>

Options
- -k, --key <API_KEY>         : Tailscale API key (recommended to pass via env var instead).
- -e, --env <ENV_VAR_NAME>    : Read API key from environment variable named ENV_VAR_NAME.
- -n, --dry-run               : Print which machines would be deleted without deleting them.
- -f, --force                 : Skip interactive confirmation and delete matches immediately.
- -h, --help                  : Show help and exit.

Examples
- Dry-run: show matching devices without deleting:
  ./delete-tailscale-machines.sh --dry-run "test-machine"

- Delete by name substring with confirmation:
  ./delete-tailscale-machines.sh "staging"

- Use environment variable for the API key:
  export TAILSCALE_API_KEY="tskey_xxx"
  ./delete-tailscale-machines.sh --env TAILSCALE_API_KEY "old-host"

Behavior and safety notes
- The script lists devices and then deletes matches. By default it asks for confirmation before deleting.
- Use --dry-run to ensure your filter matches only the devices you intend to remove.
- Deleting a device is destructive: the device will be removed from the Tailscale admin panel and will need to be re-authenticated to rejoin.
- Keep API keys secret; prefer supplying credentials via environment variables or secure secret storage.

Suggested improvements
- Add a flag to delete by device ID for exact matches.
- Add pagination handling and rate-limit backoff if you expect to operate against very large accounts.
- Add logging and an option to write a deletion audit to a secure location.

Contact / Maintainer
- If you need changes or find a bug, open an issue or a pull request in this repository.

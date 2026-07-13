# Incident 03: the DNS answer that never arrives

Difficulty: intermediate

## Ticket

The `rescue-upstream-check.service` unit on `relay` is failing even though the
local `rescue-web` application is healthy. The dependency name
`rescue-api.internal` should be supplied by the lab network's DNS service.
Restore the upstream check without replacing the service name with an IP
address or changing the application code.

Start the incident and enter the host:

```bash
./lab break 03
./lab shell
```

PowerShell users can run `.\lab.ps1 break 03` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run:

```bash
./lab verify 03
```

The verifier checks the effective host resolution result, the upstream health
endpoint and the systemd unit. It does not require a particular editor or
repair command.

## Hints

<details>
<summary>Hint 1</summary>

Inspect the failed unit, its journal and the result returned through the
operating system's normal name-service path:

```bash
sudo systemctl status rescue-upstream-check.service
sudo journalctl -u rescue-upstream-check.service --no-pager -n 30
getent ahostsv4 rescue-api.internal
```

</details>

<details>
<summary>Hint 2</summary>

Compare the normal result with a query sent directly to Docker's embedded DNS
server:

```bash
dig +short @127.0.0.11 rescue-api.internal A
grep '^hosts:' /etc/nsswitch.conf
```

If those answers differ, inspect the sources that appear before `dns` on the
`hosts:` line.

</details>

<details>
<summary>Hint 3</summary>

Inspect `/etc/hosts` for a stale local override. Remove only the incident entry,
then reset the failed state and restart `rescue-upstream-check.service`.

</details>

The full repair is in [`solutions/03-dns-ghost.md`](solutions/03-dns-ghost.md).

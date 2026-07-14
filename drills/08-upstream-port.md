# Incident 08: upstream on the wrong port

Difficulty: intermediate

## Ticket

The `rescue-upstream-port-check.service` unit is failing on `relay`. The
external upstream API is healthy, but the application probe cannot reach it.
Restore the probe without exposing the companion service to the Docker host,
disabling the unit or changing the companion container.

```bash
./lab break 08
./lab shell
```

PowerShell users can run `.\lab.ps1 break 08` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 08` or
`.\lab.ps1 verify 08`.

## Hints

<details>
<summary>Hint 1</summary>

Start with the failed unit and its recent journal. Identify the command that
systemd ran and the endpoint it tried to contact.

```bash
sudo systemctl status rescue-upstream-port-check.service
sudo journalctl -u rescue-upstream-port-check.service -n 30 --no-pager
```

</details>

<details>
<summary>Hint 2</summary>

Inspect the probe script and its configuration separately. Check name
resolution and test the configured URL with a short timeout.

```bash
sudo systemctl cat rescue-upstream-port-check.service
sudo cat /etc/rescue-upstream-port.conf
getent hosts upstream-api
```

</details>

<details>
<summary>Hint 3</summary>

Compare `/etc/rescue-upstream-port.conf` with its `.last-known-good` neighbour.
Restore the working endpoint, then restart the failed unit.

</details>

The full repair is in
[`solutions/08-upstream-port.md`](solutions/08-upstream-port.md).

# Incident 04: permission denied after maintenance

Difficulty: beginner

## Ticket

The `rescue-web` service stopped after maintenance on `relay`. Its journal says
that it cannot write `/var/lib/rescue-web/last-startup`. Restore the service
without running it as root or making the data directory world-writable.

```bash
./lab break 04
./lab shell
```

PowerShell users can run `.\lab.ps1 break 04` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 04` or
`.\lab.ps1 verify 04`.

## Hints

<details>
<summary>Hint 1</summary>

Inspect the unit identity and the precise write error:

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service --no-pager -n 30
sudo systemctl show rescue-web.service -p User -p Group
```

</details>

<details>
<summary>Hint 2</summary>

Inspect every component of the data path, then compare its owner and mode with
the account that runs the service:

```bash
namei -l /var/lib/rescue-web/last-startup
stat -c '%A %U:%G %n' /var/lib/rescue-web
```

</details>

<details>
<summary>Hint 3</summary>

Restore the intended owner and a least-privilege directory mode, then restart
the unit. Do not use `chmod 777` and do not change `User=` in the service.

</details>

The full repair is in
[`solutions/04-permission-denied.md`](solutions/04-permission-denied.md).

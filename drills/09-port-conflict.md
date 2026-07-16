# Incident 09: port conflict

Difficulty: intermediate

## Ticket

The `rescue-web.service` application is unavailable on `relay`. Its configured
port is correct, but another unauthorised systemd service is already listening
there. Restore `rescue-web`, remove the conflicting listener from the current
and next boot, and do not change the application or published port.

```bash
./lab break 09
./lab shell
```

PowerShell users can run `.\lab.ps1 break 09` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 09` or
`.\lab.ps1 verify 09`.

## Hints

<details>
<summary>Hint 1</summary>

Start with the failed application unit and its recent journal. Look for the
operating-system error reported when the process tries to start.

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service -n 30 --no-pager
```

</details>

<details>
<summary>Hint 2</summary>

Ask the kernel which process owns the expected listening socket, then inspect
that process through systemd.

```bash
sudo ss -ltnp '( sport = :8080 )'
sudo systemctl status rescue-debug-listener.service
```

</details>

<details>
<summary>Hint 3</summary>

The debug listener is not an approved production service. Stop it now, prevent
it from returning at the next boot, then reset and restart `rescue-web`.

</details>

The full repair is in
[`solutions/09-port-conflict.md`](solutions/09-port-conflict.md).

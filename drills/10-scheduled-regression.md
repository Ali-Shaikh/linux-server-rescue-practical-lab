# Incident 10: scheduled regression

Difficulty: intermediate

## Ticket

The `rescue-web.service` application on `relay` keeps moving from port 8080 to
port 8081. Restoring the known-good configuration works only briefly before the
fault returns. Find and stop the recurring cause, restore the published service
on port 8080, and prevent the bad deployment from returning after a restart.

```bash
./lab break 10
./lab shell
```

PowerShell users can run `.\lab.ps1 break 10` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 10` or
`.\lab.ps1 verify 10`.

## Hints

<details>
<summary>Hint 1</summary>

Confirm where the application listens and compare the live configuration with
its last-known-good neighbour.

```bash
sudo systemctl status rescue-web.service
sudo ss -ltnp '( sport = :8080 or sport = :8081 )'
sudo diff -u /etc/rescue-web/config.json.last-known-good /etc/rescue-web/config.json
```

</details>

<details>
<summary>Hint 2</summary>

If a correct file changes again, inspect scheduled work and recent service
activity rather than repeating the same repair.

```bash
sudo systemctl list-timers --all
sudo journalctl -u rescue-config-regression.service -n 30 --no-pager
```

</details>

<details>
<summary>Hint 3</summary>

The `rescue-config-regression.timer` unit is an unauthorised deployment job.
Disable and stop the timer before restoring the known-good configuration and
restarting `rescue-web`.

</details>

The full repair is in
[`solutions/10-scheduled-regression.md`](solutions/10-scheduled-regression.md).

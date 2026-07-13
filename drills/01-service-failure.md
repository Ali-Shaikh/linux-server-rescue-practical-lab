# Incident 01: the service that will not stay up

Difficulty: beginner

## Ticket

The `rescue-web` service on `relay` stopped responding after a configuration
change. Monitoring reports repeated restart attempts. Restore the service at
<http://127.0.0.1:8100> without replacing the unit file or disabling its
restart policy.

Start the incident and enter the host:

```bash
./lab break 01
./lab shell
```

PowerShell users can run `.\lab.ps1 break 01` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run:

```bash
./lab verify 01
```

The verifier checks the outcome only. It does not require a particular editor
or command sequence.

## Hints

<details>
<summary>Hint 1</summary>

Ask systemd for the current state of `rescue-web.service`. Pay attention to
the recent exit reason and whether it is restarting.

</details>

<details>
<summary>Hint 2</summary>

The journal contains the application's error output:

```bash
sudo journalctl -u rescue-web.service --no-pager -n 30
```

</details>

<details>
<summary>Hint 3</summary>

Compare the effective unit with the vendor unit. `systemctl cat` shows both
the original file and any drop-in overrides. The application expects a
numeric port, and its healthy default is 8080 inside the host.

</details>

The full repair is in
[`solutions/01-service-failure.md`](solutions/01-service-failure.md).

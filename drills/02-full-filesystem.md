# Incident 02: no space where the application writes

Difficulty: beginner

## Ticket

The `rescue-web` service on `relay` stopped responding during a routine data
write. The root filesystem still appears to have free space. Restore the
service at <http://127.0.0.1:8100> without changing the application code or
moving its data onto another filesystem.

Start the incident and enter the host:

```bash
./lab break 02
./lab shell
```

PowerShell users can run `.\lab.ps1 break 02` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run:

```bash
./lab verify 02
```

The verifier checks whether the application can write its startup state and
serve requests. It does not require a particular repair command.

## Hints

<details>
<summary>Hint 1</summary>

Inspect `rescue-web.service` and its recent journal. The Python exception names
the failing operation and its operating-system error.

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service --no-pager -n 30
```

</details>

<details>
<summary>Hint 2</summary>

Do not assume `/` and the application's data directory are on the same
filesystem. Ask `df` about both paths and use `findmnt` to identify the mount
that contains `/var/lib/rescue-web`.

</details>

<details>
<summary>Hint 3</summary>

Measure the files on the affected filesystem before removing anything:

```bash
sudo du -ah /var/lib/rescue-web | sort -h | tail
```

Look for an obsolete file large enough to explain the capacity loss. Remove
only that file, then restart and inspect the service.

</details>

The full repair is in
[`solutions/02-full-filesystem.md`](solutions/02-full-filesystem.md).

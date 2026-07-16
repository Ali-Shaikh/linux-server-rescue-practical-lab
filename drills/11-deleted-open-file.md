# Incident 11: deleted open file

Difficulty: intermediate

## Ticket

The `rescue-web.service` application on `relay` cannot start because its data
filesystem is full. A directory scan does not account for the used space, and
removing visible files does not recover it. Find what still owns the missing
bytes, release them safely, restore the application, and prevent the fault from
returning after a restart.

```bash
./lab break 11
./lab shell
```

PowerShell users can run `.\lab.ps1 break 11` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 11` or
`.\lab.ps1 verify 11`.

## Hints

<details>
<summary>Hint 1</summary>

Confirm the service error and compare filesystem usage with the visible files:

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service -n 30 --no-pager
df -h /var/lib/rescue-web
sudo du -xsh /var/lib/rescue-web
```

</details>

<details>
<summary>Hint 2</summary>

Linux exposes every process file descriptor below `/proc/<PID>/fd`. Search for
open descriptors whose directory entry has already been deleted:

```bash
sudo find /proc/[0-9]*/fd -maxdepth 1 -lname '* (deleted)' -ls 2>/dev/null
```

</details>

<details>
<summary>Hint 3</summary>

The PID in the `/proc/<PID>/fd/<FD>` path identifies the process retaining the
space. Ask systemd which unit owns that PID, then stop and disable the faulty
log writer before restarting `rescue-web`:

```bash
sudo systemctl status <PID>
```

</details>

The full repair is in
[`solutions/11-deleted-open-file.md`](solutions/11-deleted-open-file.md).

# Incident 13: backup sprawl

Difficulty: intermediate

## Ticket

The `rescue-web.service` application on `relay` is failing because its data
filesystem has no free space. A recently enabled local backup schedule keeps
creating archives, and deleting one file appears to help only briefly. Find
the recurring source of the growth, preserve a recent complete backup, apply
a safe retention response, and restore the application without allowing the
fault to return.

This scenario is based on a real operator incident in which application backup
automation ran without a retention policy until dependent services failed.

```bash
./lab break 13
./lab shell
```

PowerShell users can run `.\lab.ps1 break 13` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 13` or
`.\lab.ps1 verify 13`.

## Hints

<details>
<summary>Hint 1</summary>

Confirm the service error and identify which filesystem is full:

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service -n 30 --no-pager
df -h / /var/lib/rescue-web
sudo du -xah /var/lib/rescue-web | sort -h | tail -n 20
```

</details>

<details>
<summary>Hint 2</summary>

The large files are outputs, not the complete cause. Inspect scheduled jobs and
the service that writes those archives:

```bash
sudo systemctl list-timers --all
sudo systemctl status rescue-backup.timer rescue-backup.service
sudo journalctl -u rescue-backup.service -n 30 --no-pager
```

</details>

<details>
<summary>Hint 3</summary>

Stop the unsafe schedule before reclaiming space. Inspect timestamps, sizes and
names carefully, preserve the newest complete archive, remove the incomplete
and confirmed older copies, then restart `rescue-web.service`.

An alternative safe repair may keep the timer enabled if the backup job is
changed to enforce a working retention policy.

</details>

The full repair is in
[`solutions/13-backup-sprawl.md`](solutions/13-backup-sprawl.md).

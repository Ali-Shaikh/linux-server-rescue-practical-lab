# Incident 12: inode exhaustion

Difficulty: intermediate

## Ticket

The `rescue-web.service` application on `relay` cannot start. Operators report
that its data filesystem still has plenty of free space, but the journal says
`No space left on device`. Identify the capacity that is actually exhausted,
remove only the obsolete application artefacts responsible, and restore the
service without discarding unrelated data.

```bash
./lab break 12
./lab shell
```

PowerShell users can run `.\lab.ps1 break 12` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 12` or
`.\lab.ps1 verify 12`.

## Hints

<details>
<summary>Hint 1</summary>

Confirm the service error, then inspect both block and inode capacity on the
application filesystem:

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service -n 30 --no-pager
df -h /var/lib/rescue-web
df -i /var/lib/rescue-web
```

</details>

<details>
<summary>Hint 2</summary>

An inode represents a filesystem object. Count objects without crossing into
another filesystem, then identify which application directory contains the
large collection:

```bash
sudo find /var/lib/rescue-web -xdev -printf '.' | wc -c
sudo find /var/lib/rescue-web -xdev -maxdepth 2 -type f -printf '%h\n' \
  | sort | uniq -c | sort -n
```

</details>

<details>
<summary>Hint 3</summary>

Inspect filenames and timestamps before deleting anything. Remove only the
obsolete session files that match the stale-session naming convention, then
restart the application:

```bash
sudo find /var/lib/rescue-web/sessions -xdev -type f \
  -name 'stale-*.session' -print
```

</details>

The full repair is in
[`solutions/12-inode-exhaustion.md`](solutions/12-inode-exhaustion.md).

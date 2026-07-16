# Solution: incident 11

<details>
<summary>Reveal one safe repair</summary>

The service journal reports `No space left on device`, but the visible files do
not explain the full filesystem. Compare allocated space with directory entries:

```bash
df -h /var/lib/rescue-web
sudo du -xsh /var/lib/rescue-web
```

An unlinked file continues to consume space while a process holds its file
descriptor open. Find deleted descriptors through procfs:

```bash
sudo find /proc/[0-9]*/fd -maxdepth 1 -lname '* (deleted)' -ls 2>/dev/null
```

The matching path contains the holder PID as `/proc/<PID>/fd/<FD>`. Map that PID
back to its systemd unit, then stop and disable the faulty log-retention worker:

```bash
sudo systemctl status <PID>
sudo systemctl disable --now rescue-deleted-log-holder.service
df -h /var/lib/rescue-web
```

Closing the final descriptor releases the filesystem blocks. Restart the
application and verify its endpoint:

```bash
sudo systemctl reset-failed rescue-web.service
sudo systemctl restart rescue-web.service
sudo systemctl status rescue-web.service
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 11` or `.\lab.ps1 verify 11`.

</details>

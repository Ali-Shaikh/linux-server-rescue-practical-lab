# Solution: incident 13

<details>
<summary>Reveal one safe repair</summary>

The application journal reports `No space left on device`. Confirm that the
bounded application filesystem, rather than the root filesystem, is full and
identify the archive growth:

```bash
df -h / /var/lib/rescue-web
sudo du -xah /var/lib/rescue-web | sort -h | tail -n 20
sudo systemctl list-timers --all
sudo systemctl status rescue-backup.timer rescue-backup.service
```

Stop and disable the unsafe schedule before deleting data. Then list the files
in timestamp order and confirm which archive is newest and complete:

```bash
sudo systemctl disable --now rescue-backup.timer
sudo systemctl stop rescue-backup.service
sudo find /var/lib/rescue-web/backups -xdev -maxdepth 1 -type f \
  -printf '%T@ %s %p\n' | sort -n
```

For this incident, `backup-0003.tar` is the newest complete archive. Remove the
incomplete fourth attempt and the two confirmed older copies, while preserving
that recent backup:

```bash
sudo rm -- \
  /var/lib/rescue-web/backups/.backup-0004.tar.partial \
  /var/lib/rescue-web/backups/backup-0001.tar \
  /var/lib/rescue-web/backups/backup-0002.tar
df -h /var/lib/rescue-web
```

Reset the failed application state, restart it and prove its endpoint:

```bash
sudo systemctl reset-failed rescue-backup.service rescue-web.service
sudo systemctl restart rescue-web.service
sudo systemctl status rescue-web.service
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 13` or `.\lab.ps1 verify 13`. The verifier
also observes multiple original timer intervals, so deleting an archive without
stopping the unsafe recurrence will not pass.

</details>

# Solution: incident 12

<details>
<summary>Reveal one safe repair</summary>

`No space left on device` can refer to exhausted inodes even when filesystem
blocks remain available. Compare both resources:

```bash
df -h /var/lib/rescue-web
df -i /var/lib/rescue-web
```

The block view has free capacity while the inode view is at 100%. Inspect the
objects consuming those inodes and confirm the stale-session pattern before
removing anything:

```bash
sudo find /var/lib/rescue-web -xdev -printf '.' | wc -c
sudo find /var/lib/rescue-web/sessions -xdev -type f \
  -name 'stale-*.session' -print
```

Delete only the obsolete session files, verify that inodes are available, then
restart the application:

```bash
sudo find /var/lib/rescue-web/sessions -xdev -type f \
  -name 'stale-*.session' -delete
df -i /var/lib/rescue-web
sudo systemctl reset-failed rescue-web.service
sudo systemctl restart rescue-web.service
sudo systemctl status rescue-web.service
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 12` or `.\lab.ps1 verify 12`.

</details>

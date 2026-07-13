# Solution: incident 02

<details>
<summary>Reveal one safe repair</summary>

Start with the service evidence:

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service --no-pager -n 30
```

The journal reports `No space left on device` while writing
`/var/lib/rescue-web/last-startup`. Inspect the filesystem for that path rather
than relying only on the root filesystem:

```bash
df -h / /var/lib/rescue-web
findmnt --target /var/lib/rescue-web
sudo du -ah /var/lib/rescue-web | sort -h | tail
```

`old-debug.log` consumes the bounded application filesystem. Remove the
obsolete file, then start the service and verify its endpoint:

```bash
sudo rm /var/lib/rescue-web/old-debug.log
sudo systemctl reset-failed rescue-web.service
sudo systemctl restart rescue-web.service
sudo systemctl status rescue-web.service
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 02` or `.\lab.ps1 verify 02`.

</details>

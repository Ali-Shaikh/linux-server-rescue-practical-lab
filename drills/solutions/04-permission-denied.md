# Solution: incident 04

<details>
<summary>Reveal one safe repair</summary>

The service runs as `rescue`, while the application data directory was left
owned by `root:root` with no write permission for the service account.

```bash
sudo systemctl show rescue-web.service -p User -p Group
stat -c '%A %U:%G %n' /var/lib/rescue-web
sudo chown rescue:rescue /var/lib/rescue-web
sudo chmod 0750 /var/lib/rescue-web
sudo systemctl reset-failed rescue-web.service
sudo systemctl restart rescue-web.service
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 04` or `.\lab.ps1 verify 04`.

</details>

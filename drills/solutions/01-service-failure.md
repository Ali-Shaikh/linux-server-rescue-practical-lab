# Solution: incident 01

<details>
<summary>Reveal one safe repair</summary>

Inspect the failure and the effective unit:

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service --no-pager -n 30
sudo systemctl cat rescue-web.service
```

The drop-in sets `APP_PORT` to text, but the Python service requires a number.
Correct the drop-in while keeping the vendor unit unchanged:

```bash
sudo mkdir -p /etc/systemd/system/rescue-web.service.d
printf '[Service]\nEnvironment=APP_PORT=8080\n' \
  | sudo tee /etc/systemd/system/rescue-web.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart rescue-web.service
sudo systemctl status rescue-web.service
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 01` or `.\lab.ps1 verify 01`.

</details>

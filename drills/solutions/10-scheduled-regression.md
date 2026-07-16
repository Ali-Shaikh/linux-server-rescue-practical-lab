# Solution: incident 10

<details>
<summary>Reveal one safe repair</summary>

The configuration is valid, but a recurring systemd timer deploys the wrong
port again after each superficial repair. Confirm the live difference and find
the scheduled job:

```bash
sudo diff -u /etc/rescue-web/config.json.last-known-good /etc/rescue-web/config.json
sudo systemctl list-timers --all
sudo systemctl status rescue-config-regression.timer
sudo journalctl -u rescue-config-regression.service -n 30 --no-pager
```

Disable the unauthorised timer before restoring the known-good configuration.
Then restart the application and confirm that it remains on port 8080:

```bash
sudo systemctl disable --now rescue-config-regression.timer
sudo systemctl stop rescue-config-regression.service
sudo install -o root -g root -m 0644 \
  /etc/rescue-web/config.json.last-known-good \
  /etc/rescue-web/config.json
sudo systemctl reset-failed rescue-web.service
sudo systemctl restart rescue-web.service
sudo ss -ltnp '( sport = :8080 or sport = :8081 )'
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 10` or `.\lab.ps1 verify 10`.

</details>

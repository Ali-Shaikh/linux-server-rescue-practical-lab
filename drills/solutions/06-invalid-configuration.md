# Solution: incident 06

<details>
<summary>Reveal one safe repair</summary>

The deployed JSON has a trailing comma. Validate it and inspect the supplied
rollback before making a change:

```bash
python3 -m json.tool /etc/rescue-web/config.json
sudo diff -u /etc/rescue-web/config.json.last-known-good /etc/rescue-web/config.json
python3 -m json.tool /etc/rescue-web/config.json.last-known-good
```

Restore the known-good file with its intended ownership and mode, then restart
and verify the service:

```bash
sudo install -o root -g root -m 0644 \
  /etc/rescue-web/config.json.last-known-good \
  /etc/rescue-web/config.json
sudo systemctl reset-failed rescue-web.service
sudo systemctl restart rescue-web.service
sudo systemctl status rescue-web.service
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 06` or `.\lab.ps1 verify 06`.

</details>

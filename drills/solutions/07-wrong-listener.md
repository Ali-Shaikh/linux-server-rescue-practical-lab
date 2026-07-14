# Solution: incident 07

<details>
<summary>Reveal one safe repair</summary>

The service is healthy on `127.0.0.1:8080`, but Docker forwards traffic to the
container's network interface. Confirm the mismatch:

```bash
ip -4 -brief address
sudo ss -ltnp '( sport = :8080 )'
sudo diff -u /etc/rescue-web/config.json.last-known-good /etc/rescue-web/config.json
```

Restore the configuration that binds to all container interfaces, then restart
the service:

```bash
sudo install -o root -g root -m 0644 \
  /etc/rescue-web/config.json.last-known-good \
  /etc/rescue-web/config.json
sudo systemctl restart rescue-web.service
sudo ss -ltnp '( sport = :8080 )'
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 07` or `.\lab.ps1 verify 07`.

</details>

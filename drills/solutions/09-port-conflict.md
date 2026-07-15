# Solution: incident 09

<details>
<summary>Reveal one safe repair</summary>

The application is configured for the correct port, but an unauthorised debug
service starts first and owns its socket. Confirm the failed bind and identify
the listener:

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service -n 30 --no-pager
sudo ss -ltnp '( sport = :8080 )'
sudo systemctl status rescue-debug-listener.service
```

Stop and disable the debug listener so it cannot return after a restart. Then
clear the application failure and start it again:

```bash
sudo systemctl disable --now rescue-debug-listener.service
sudo systemctl reset-failed rescue-web.service
sudo systemctl restart rescue-web.service
sudo systemctl status rescue-web.service --no-pager
sudo ss -ltnp '( sport = :8080 )'
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 09` or `.\lab.ps1 verify 09`.

</details>

# Solution: incident 08

<details>
<summary>Reveal one safe repair</summary>

The companion API is reachable only inside the Compose network. The probe is
using the right service name and path but the wrong port. Confirm the failed
request and compare the saved configuration:

```bash
sudo systemctl status rescue-upstream-port-check.service
sudo journalctl -u rescue-upstream-port-check.service -n 30 --no-pager
sudo diff -u \
  /etc/rescue-upstream-port.conf.last-known-good \
  /etc/rescue-upstream-port.conf
```

Restore the known-good endpoint and rerun the systemd probe:

```bash
sudo install -o root -g root -m 0644 \
  /etc/rescue-upstream-port.conf.last-known-good \
  /etc/rescue-upstream-port.conf
sudo systemctl reset-failed rescue-upstream-port-check.service
sudo systemctl restart rescue-upstream-port-check.service
sudo systemctl status rescue-upstream-port-check.service --no-pager
```

Exit the host and run `./lab verify 08` or `.\lab.ps1 verify 08`.

</details>

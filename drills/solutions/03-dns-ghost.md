# Solution: incident 03

<details>
<summary>Reveal one safe repair</summary>

Compare the host resolver with Docker's DNS answer and inspect NSS ordering:

```bash
getent ahostsv4 rescue-api.internal
dig +short @127.0.0.11 rescue-api.internal A
grep '^hosts:' /etc/nsswitch.conf
grep 'rescue-api.internal' /etc/hosts
```

The tagged `/etc/hosts` entry is selected before DNS. Remove only that entry
without replacing Docker's mounted hosts file:

```bash
grep -v 'cloudsprocket-dns-ghost' /etc/hosts > /tmp/hosts.clean
sudo sh -c 'cat /tmp/hosts.clean > /etc/hosts'
rm /tmp/hosts.clean
sudo systemctl reset-failed rescue-upstream-check.service
sudo systemctl restart rescue-upstream-check.service
sudo systemctl status rescue-upstream-check.service
getent ahostsv4 rescue-api.internal
```

Exit the host and run `./lab verify 03` or `.\lab.ps1 verify 03`.

</details>

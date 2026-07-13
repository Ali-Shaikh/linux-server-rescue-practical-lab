# Solution: incident 05

<details>
<summary>Reveal one safe repair</summary>

Identify the process before changing it:

```bash
ps -eo pid,ppid,user,ni,pcpu,comm,args --sort=-pcpu | head
sudo systemctl status rescue-cpu-hog.service
sudo systemctl show rescue-cpu-hog.service -p MainPID -p Restart -p CPUQuotaPerSecUSec
```

The compatibility worker is managed with `Restart=always`. Stop and disable
the unit so systemd does not recreate it now or at the next normal boot:

```bash
sudo systemctl disable --now rescue-cpu-hog.service
sudo systemctl is-active rescue-cpu-hog.service
sudo systemctl is-enabled rescue-cpu-hog.service
curl --fail http://127.0.0.1:8080/health
```

Exit the host and run `./lab verify 05` or `.\lab.ps1 verify 05`.

</details>

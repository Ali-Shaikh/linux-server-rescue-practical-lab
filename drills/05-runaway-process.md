# Incident 05: the worker that will not stay stopped

Difficulty: intermediate

## Ticket

Monitoring reports sustained CPU use on `relay`, although `rescue-web` still
answers requests. Find the unexpected workload and stop it from returning.
Do not increase its CPU allowance, reboot the host or kill an unexplained PID
without identifying its owner.

```bash
./lab break 05
./lab shell
```

PowerShell users can run `.\lab.ps1 break 05` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 05` or
`.\lab.ps1 verify 05`.

## Hints

<details>
<summary>Hint 1</summary>

List processes by CPU use and keep the full command line visible:

```bash
ps -eo pid,ppid,user,ni,pcpu,comm,args --sort=-pcpu | head
```

</details>

<details>
<summary>Hint 2</summary>

Once you identify the process, inspect its cgroup and owning systemd unit:

```bash
cat /proc/PID/cgroup
sudo systemctl status rescue-cpu-hog.service
sudo systemctl show rescue-cpu-hog.service -p MainPID -p Restart -p CPUQuotaPerSecUSec
```

Replace `PID` with the process identifier you found.

</details>

<details>
<summary>Hint 3</summary>

Stopping only the process is temporary because systemd restarts it. Stop and
disable the owning unit, then confirm both its active and enabled states.

</details>

The full repair is in
[`solutions/05-runaway-process.md`](solutions/05-runaway-process.md).

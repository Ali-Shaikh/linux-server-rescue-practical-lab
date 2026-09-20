# Solution: incident 01

<details>
<summary>Reveal one safe repair</summary>

## Inspect

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service --no-pager -n 30
sudo systemctl cat rescue-web.service
```

- `status` is the live unit: active, restarting, or failed, and the last exit.
- `journalctl -u` is that unit's log. `--no-pager` prints to the terminal
  instead of opening a scrollable pager. `-n 30` is the last thirty lines.
- `systemctl cat` prints the vendor unit **and** any drop-in files merged
  on top of it. That merge is what systemd actually runs.

You should see a drop-in that sets `APP_PORT=not-a-port`. The application
needs a number. The healthy listen port **inside** this host is `8080`.
`http://127.0.0.1:8100` is the same service published on your laptop; from
`lab shell` you curl `8080`.

Do not edit the vendor unit under `/usr/lib` or `/lib`. Package updates
replace that file. Local changes belong in a drop-in under `/etc`.

## Repair the drop-in

systemd reads extra settings from
`/etc/systemd/system/<unit>.d/*.conf`. For this unit that directory is
`rescue-web.service.d`. The incident already created it; `mkdir -p` is
still the right habit: it creates any missing parent, and it does nothing
harmful if the directory is already there.

```bash
sudo mkdir -p /etc/systemd/system/rescue-web.service.d
```

Now replace the bad drop-in. `tee` copies what it reads on stdin to a file
(and also prints it). You need `sudo tee` because this does **not** write
as root:

```bash
sudo printf '[Service]\nEnvironment=APP_PORT=8080\n' \
  > /etc/systemd/system/rescue-web.service.d/override.conf
```

The shell applies `>` as your user **before** `sudo` runs, so the write is
denied. Piping into `sudo tee` makes the write itself privileged:

```bash
printf '[Service]\nEnvironment=APP_PORT=8080\n' \
  | sudo tee /etc/systemd/system/rescue-web.service.d/override.conf
```

`printf` does not need `sudo`. Only the write does.

systemd will not notice a unit file change until you tell it to re-read
disk, then start a new process from that merged unit:

```bash
sudo systemctl daemon-reload
sudo systemctl restart rescue-web.service
sudo systemctl status rescue-web.service
curl --fail http://127.0.0.1:8080/health
```

Leave `lab shell` (`exit`). `verify` is a host command, not something
inside `relay`:

```bash
./lab verify 01
```

PowerShell: `.\lab.ps1 verify 01`.

</details>

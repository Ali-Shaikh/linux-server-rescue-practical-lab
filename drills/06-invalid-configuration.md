# Incident 06: the configuration that passed review

Difficulty: intermediate

## Ticket

`rescue-web` stopped after a configuration deployment on `relay`. Restore the
service using the evidence and rollback material already on the host. Do not
modify the application, bypass its configured file or replace the service with
an ad hoc process.

```bash
./lab break 06
./lab shell
```

PowerShell users can run `.\lab.ps1 break 06` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 06` or
`.\lab.ps1 verify 06`.

## Hints

<details>
<summary>Hint 1</summary>

Inspect the service status and journal. The exception identifies the file and
the parser that rejected it:

```bash
sudo systemctl status rescue-web.service
sudo journalctl -u rescue-web.service --no-pager -n 30
sudo systemctl cat rescue-web.service
```

</details>

<details>
<summary>Hint 2</summary>

Validate the deployed file independently of the service:

```bash
python3 -m json.tool /etc/rescue-web/config.json
```

Then inspect the nearby rollback material before using it.

</details>

<details>
<summary>Hint 3</summary>

Compare the deployed and last-known-good files. Restore a valid configuration
atomically, restart the service and inspect both its status and health endpoint.

</details>

The full repair is in
[`solutions/06-invalid-configuration.md`](solutions/06-invalid-configuration.md).

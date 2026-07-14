# Incident 07: healthy on the wrong interface

Difficulty: intermediate

## Ticket

The `rescue-web` health check is green inside `relay`, but the published
service at <http://127.0.0.1:8100> is unavailable from the Docker host. Restore
the published path without changing the Compose port, adding host networking or
disabling the container health check.

```bash
./lab break 07
./lab shell
```

PowerShell users can run `.\lab.ps1 break 07` and `.\lab.ps1 shell`.

When the repair is complete, leave the shell and run `./lab verify 07` or
`.\lab.ps1 verify 07`.

## Hints

<details>
<summary>Hint 1</summary>

Compare loopback with the container's non-loopback address:

```bash
ip -4 -brief address
curl --fail http://127.0.0.1:8080/health
curl --fail http://CONTAINER_ADDRESS:8080/health
```

</details>

<details>
<summary>Hint 2</summary>

Ask the kernel which local address owns the listener and which process opened
it:

```bash
sudo ss -ltnp '( sport = :8080 )'
sudo systemctl cat rescue-web.service
```

</details>

<details>
<summary>Hint 3</summary>

Inspect `/etc/rescue-web/config.json` and its last-known-good neighbour. The
service must listen on an address reachable through the container network, not
only its own loopback interface.

</details>

The full repair is in
[`solutions/07-wrong-listener.md`](solutions/07-wrong-listener.md).

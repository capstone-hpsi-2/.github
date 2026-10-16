# Connect to the dev VM

The dev VM sits behind Cloudflare Access, so plain `ssh` cannot reach it. `cloudflared` opens the tunnel and gets you a short-lived certificate after a browser login. Steps 1 to 4 are required; 5 and 6 are optional.

## 1. Install cloudflared

Download it from the [cloudflared releases](https://github.com/cloudflare/cloudflared/releases/) and put it on your `PATH`. Check: `cloudflared --version`.

## 2. Add the SSH config

Open the config file in a terminal:

```
notepad ~/.ssh/config
```

Paste this in:

```
Match host *.ssisporttech.com exec "cloudflared.exe access ssh-gen --hostname %h"
  ProxyCommand cloudflared access ssh --hostname %h
  IdentityFile "~\.cloudflared\%h-cf_key"
  CertificateFile "~\.cloudflared\%h-cf_key-cert.pub"
```

Save it as `config` with no extension. Notepad saves `config.txt` by default, and ssh ignores that file. Check: `ls ~/.ssh` lists `config`, not `config.txt`.

How it works: for any `*.ssisporttech.com` host, `ssh-gen` fetches a certificate (it opens a browser for the Cloudflare login the first time), and `ProxyCommand` carries the connection through the tunnel.

On macOS or Linux, write `cloudflared` instead of `cloudflared.exe` and use `/` in the two paths.

## 3. Get the host and user

This repo is public, so the VM's host and user are not written here. In the `.github` checkout:

1. Copy `.env.example` to `.env.local`. Git ignores `.env.local`.
2. Paste in the two lines from the team chat.
3. Load them into your shell:

PowerShell:

```
Get-Content .env.local | Where-Object { $_ -match '^\w+=' } | ForEach-Object { $k, $v = $_ -split '=', 2; Set-Item "env:$k" $v }
```

macOS or Linux:

```
set -a; . ./.env.local; set +a
```

## 4. Connect

`PRIVATE_KEY_NAME` is the private key IT gave you. Keep it in `~/.ssh` and never commit it.

PowerShell:

```
ssh -i ~/.ssh/PRIVATE_KEY_NAME "$env:VM_SSH_USER@$env:VM_SSH_HOST"
```

macOS or Linux:

```
ssh -i ~/.ssh/PRIVATE_KEY_NAME "$VM_SSH_USER@$VM_SSH_HOST"
```

On Windows, use PowerShell or Command Prompt, not Git Bash. Git Bash's ssh runs the `ProxyCommand` through bash, which cannot start `cloudflared.exe`, and the connection hangs.

## 5. Optional: open the VM in VS Code

1. Install the Remote - SSH extension, which adds the Remote Explorer view.
2. Add a host block to `~/.ssh/config`, with the values from `.env.local`:
   ```
   Host cwsp-dev-vm
     HostName <VM_SSH_HOST>
     User <VM_SSH_USER>
     IdentityFile ~/.ssh/PRIVATE_KEY_NAME
   ```
   Put it above the `Match` block. The `Match` block still applies, because ssh checks it against `HostName`.
3. In Remote Explorer, pick `cwsp-dev-vm`. The same block also makes `ssh cwsp-dev-vm` work.

## 6. Optional: transfer files

PowerShell:

```
sftp -i ~/.ssh/PRIVATE_KEY_NAME "$env:VM_SSH_USER@$env:VM_SSH_HOST"
```

Then `put local-file` uploads and `get remote-file` downloads. Never copy secrets, `.env.local` files or clinical data onto the VM: it is shared.

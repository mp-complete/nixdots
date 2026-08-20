# Proposal: secret key custody — `/etc` vs `$HOME`, and multi-recipient host onboarding

Status: proposal. Nothing in this document is implemented yet.

## Current state (what I found)

- `.sops.yaml` declares **one** age recipient (`&age_generic age12dpenp32wd…`) across two
  creation rules. All six encrypted files resolve to that single recipient — no drift,
  but also no per-host separation.
- That identity lives at `~/.config/sops/age/keys.txt` (mode 0600, user `miles`) and holds
  two identities; only the first is a recipient of anything in this repo.
- `modules/flake/secrets.nix` points the NixOS layer at `/etc/nixos/keys.txt`, which
  **only exists on euler** — the sole host using `mounts` / `wireguard` / `forgejo-runner`.
- Everywhere else the home-manager layer is the only one that works, which is why
  `modules/wsl/gpg-bootstrap.nix` and `modules/ai/_impl/secrets.nix` both use HM sops.
- `modules/system/ssh.nix` enables openssh in `base`, so **every host already has
  `/etc/ssh/ssh_host_ed25519_key`** — and sops-nix defaults `sops.age.sshKeyPaths` to
  exactly the ed25519 keys from `services.openssh.hostKeys`. The infrastructure for
  per-host identities is already present and unused.

## The rule

> **The identity that can decrypt a secret should live at the narrowest trust level that
> still has to read it.**
>
> System-wide, machine-scoped, or agent-adjacent secrets → `/etc` (root-owned identity,
> handed to users per-secret via `owner`/`mode`).
> Secrets that only ever make sense inside one user's session, on a machine where you are
> not root → `$HOME`.

Corollary, and the point that matters most here: **an identity that decrypts *every*
secret in the repo is not a user-level secret.** It is infrastructure. It belongs to root.

## Which layer for which secret

| Layer | Identity | Secret lands in | Use when |
|---|---|---|---|
| **NixOS** (`/etc`) | `/etc/ssh/ssh_host_ed25519_key` (root, 0600) | `/run/secrets/<n>`, tmpfs, explicit `owner`/`mode` | Default. System services, machine-scoped credentials, anything a daemon reads, and any secret that must survive without a logind session |
| **home-manager** (`$HOME`) | `~/.config/sops/age/keys.txt` | `%r/secrets.d`, per-user tmpfs | Only when root genuinely cannot be involved: non-NixOS hosts, standalone HM, or shared machines where you are not root |

Applied to what exists today:

| Secret | Consumer | Ideal layer |
|---|---|---|
| `secrets/wireguard.yaml` | `networking.wireguard` (root daemon) | `/etc` — already correct |
| `secrets/general.yaml` → `truenas` | `mount.cifs` (kernel/root) | `/etc` — already correct |
| `secrets/general.yaml` → `forgejo-runner-token` | systemd service | `/etc` — already correct |
| `modules/wsl/gpg-key.enc.yaml` | user gpg keyring | `/etc`, delivered `owner = miles` |
| `modules/ai/_impl/api-keys.enc.yaml` | copilot-cli / opencode as `miles` | `/etc`, delivered `owner = miles` |
| `modules/shell/atuin-key.enc.yaml` | atuin as `miles` | `/etc`, delivered `owner = miles` |

The last three are the interesting ones. They are consumed by user processes, which makes
`$HOME` *look* right — but the thing being protected is the identity, not the secret. Under
the current design any process running as `miles` reads `keys.txt` and thereby decrypts
wireguard configs, TrueNAS credentials, and API keys too. That matters concretely in this
repo because `modules/ai/` runs LLM agents as `miles` with shell access: one prompt
injection is a total compromise of the key material, not of one secret.

Under the ideal design a compromised user account reads the three files root chose to hand
it, and nothing else — and no future secret is exposed by default.

## Identity model: per-host keys plus an admin key

Two classes of recipient, and every encrypted file is encrypted to **both** classes:

1. **Host identities** — one per machine, derived from that machine's SSH host key.
   The private half never leaves the machine and is never copied, backed up, or typed.
   A host can decrypt; it can never re-key.
2. **One admin identity** — the root of trust. Held offline, passphrase-protected, and
   *not* installed on any host. Its only job is to decrypt-and-re-encrypt when the
   recipient set changes. This is the key that makes onboarding and revocation possible
   at all: without it, adding a host would require an existing host's private key.

The admin key is the natural home for the current `age12dpen…`. A good storage spot is the
`pass` store that `modules/wsl/gpg-bootstrap.nix` already provisions, which puts it behind
the GPG key rather than beside it as a bare file.

```yaml
# .sops.yaml
keys:
  - &admin     age12dpenp32wd…      # offline, laptop/pass only, never deployed
  - &euler     age1…                # ssh-to-age of each host's ssh_host_ed25519_key.pub
  - &laplace   age1…
  - &hilbert   age1…
  - &general2  age1…
  - &nixos     age1…

creation_rules:
  # Host-scoped: only the machines that actually run the service
  - path_regex: secrets/wireguard\.yaml$
    key_groups: [ age: [ *admin, *euler ] ]

  # Fleet-wide user secrets
  - path_regex: (secrets/[^/]+|.*\.enc)\.(yaml|json|env|ini)$
    key_groups: [ age: [ *admin, *euler, *laplace, *hilbert, *general2, *nixos ] ]
```

Note the second win, beyond blast radius: recipient lists become **per-secret**. The
wireguard config stops being decryptable by three WSL boxes that have no business with it.
The single shared identity makes that impossible today.

## Onboarding a new host

The host generates its own identity; you never transport a private key.

```bash
# 1. On the new host — nothing to install. The key already exists after first boot,
#    because services.openssh is in `base`.
ssh-keygen -A                                    # only if sshd never started
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub  # prints age1…

# 2. On your laptop, holding the admin key — add the recipient
$EDITOR .sops.yaml                               # add &newhost, add to key_groups

# 3. Re-encrypt every affected file to the new recipient set.
#    Decrypts with the admin key, re-encrypts to admin + all hosts. Values never change,
#    and no plaintext is written to disk.
sops updatekeys secrets/general.yaml
sops updatekeys modules/shell/atuin-key.enc.yaml
# …or: fd -e yaml -E '.sops.yaml' | xargs -n1 sops updatekeys --yes

# 4. Commit, then switch on the new host. It decrypts with its own host key.
```

Step 3 is the only step that needs the admin key, and it happens on your machine, not the
new host. That is the whole point of the two-class model: **hosts get read access,
you keep write access.**

Nix side: nothing to configure. sops-nix already defaults to the ed25519 host keys, so
`modules/flake/secrets.nix` shrinks to dropping the `age.keyFile` line entirely.

## Rotation and offboarding

- **Retire a host** — delete its anchor from `.sops.yaml`, `sops updatekeys` everything,
  then **rotate the underlying secret values**. Re-keying alone is not revocation: that
  host already saw the plaintext. This is the sops property SecretSpec's docs criticise,
  and it is real, but it applies per-host instead of fleet-wide once identities are split.
- **Rebuilt WSL distro** — regenerating the rootfs regenerates the SSH host key, so that
  host loses access until step 1–3 are repeated. Expected and cheap; the admin key means it
  is never a lockout. This is the main ongoing cost of the model, and it is why the admin
  key must not itself live on a WSL host.
- **Compromised admin key** — the only all-or-nothing event left: generate a new admin
  identity, `updatekeys` everything, rotate all values. Same work as today's single-key
  compromise, but now it is the *rare* case rather than the case triggered by any user-level
  compromise on any machine.

## Migration path

Ordered so nothing is ever locked out:

1. Add all five host recipients **alongside** the existing `age_generic` and
   `sops updatekeys`. Every host can now decrypt two ways; nothing has changed behaviourally.
2. Drop `sops.age.keyFile = "/etc/nixos/keys.txt"` from `modules/flake/secrets.nix` and let
   the ssh-host-key default take over. Verify a rebuild on euler.
3. Move the three user-facing secrets from HM sops to NixOS sops with `owner = config.username`,
   HM referencing `osConfig.sops.secrets.<n>.path`. Affects `wsl/gpg-bootstrap.nix`,
   `ai/_impl/secrets.nix`, and `shell/atuin.nix`. The `mkForce` activation workaround in
   gpg-bootstrap.nix can likely be deleted as part of this — it exists to work around HM sops
   activation ordering that no longer applies.
4. Only once 1–3 are switched and verified on every host: remove `age_generic` from the
   recipient list, `updatekeys`, and demote the key to offline admin-only storage.
5. Optional: tighten `creation_rules` so host-scoped secrets list only the hosts that need them.

Step 4 is the one that actually closes the blast-radius gap. Steps 1–3 are reversible;
step 4 is the commitment.

## Costs, stated honestly

- Five recipients instead of one means `sops updatekeys` becomes a routine step, and
  forgetting it on a new file produces a confusing "cannot decrypt" on exactly one host.
- WSL host-key churn adds a recurring 3-command chore.
- Step 3 is a real refactor of three modules, and a mistake there fails HM activation —
  which in this repo fails the whole `nixos-rebuild switch`, since home-manager runs inside it.
- Against that: the current setup has a single user-readable key that decrypts everything,
  on machines that run LLM agents as that user. The asymmetry is what justifies the work.

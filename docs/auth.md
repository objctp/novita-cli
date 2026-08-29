# nv auth
Manage Novita API credentials in a stable per-user store.
This store survives any install method — including an npm global install
whose files live inside node_modules and are wiped on every `npm upgrade`.
One key per account, exactly one "active" account used for API calls,
switchable with `nv auth switch`.
Layout under $NV_CONFIG_HOME:
  credentials.d/<name>   one account: NOVITA_API_KEY
  active                 a file containing the name of the active account
There is no OAuth/browser login — Novita is API-key only, so `login` just
captures and stores the key you copy from novita.ai account settings.

```
nv auth <verb> [flags]
```

## Commands

- [`nv auth use`](auth-use.md) — Alias for `nv auth switch <name>` — change the active account.
- [`nv auth login`](auth-login.md) — Store a Novita API key as an account (additive — does not replace others).
- [`nv auth logout`](auth-logout.md) — Remove an account.
- [`nv auth switch`](auth-switch.md) — Change the active account — the one used for all API calls.
- [`nv auth list`](auth-list.md) — Show stored accounts, marking the active one.
- [`nv auth status`](auth-status.md) — Show the active account and whether an API key is configured.

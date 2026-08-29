# nv auth login
Store a Novita API key as an account (additive — does not replace others).
Login marks it active; the key then loads automatically on every `nv` call.

```
nv auth login [--name <n>] [--api-key <k>] [--key-file <path>]
```

## Options

```
  --name <n>         account name (default: "default")
  --api-key <k>      API key to store (non-interactive)
  --key-file <path>  store a NOVITA_API_KEY_FILE pointer instead of the key
                     itself (useful for mounted secrets)
```

## Notes
  With no flags, prompts interactively at a terminal (input hidden), or reads
  the API key from the first stdin line when piped. Stored unquoted at
  $NV_CONFIG_HOME/credentials.d/<name> (mode 600, dir 700); other lines there
  are preserved. The API key is the only auth Novita supports — no OAuth.

# Secret Service KeePass CLI

Small helper used by the secret-service deployment backend to read secrets from a local KeePass database.

## Features

- Reads KeePass databases via the Rust `keepass` crate.
- Resolves entries by path, where the last path segment is the entry title and preceding segments are KeePass groups.
- Returns either the entry password or one attachment on stdout.
- Supports password auth through `SECRET_SERVICE_KEEPASS_PASSWORD`, `--password-file`, or an interactive prompt.
- Supports password-only, keyfile-only, and password+keyfile authentication.
- Treats an empty password from env/file/prompt as “no password component”, which keeps keyfile-only databases usable.
- Accepts standard KeePass key files, including XML key files, raw 32-byte key files, and 64-character hex-text key files.
- Supports batch validation and batch reads so one database unlock can serve many secret lookups.

## Commands

- `read`: Reads one secret and writes the raw bytes to stdout.
- `validate`: Checks that one requested secret exists and is readable.
- `batch-validate`: Validates many requests read from stdin after a single database unlock.
- `batch-read`: Reads many requests from stdin after a single database unlock and returns a JSON response on stdout.

## Batch Request Format

`batch-validate` and `batch-read` consume a JSON array from stdin like this:

```json
[
  {
    "label": "nginx/tls-cert",
    "entryPath": "infra/prod/nginx",
    "content": "attachment",
    "attachmentName": "tls.crt"
  },
  {
    "label": "nginx/basic-auth",
    "entryPath": "infra/prod/nginx-basic-auth",
    "content": "password"
  }
]
```

- `entryPath` is required.
- `content` defaults to `attachment`.
- `attachmentName` is optional and only used for attachment reads.
- `label` is optional and is echoed back in the response so callers can correlate results with their own staging logic.
- `entryPath` is also echoed back in the response, so callers can identify results by the original KeePass lookup key.

## Batch Read Response Format

`batch-read` writes JSON to stdout. Secret bytes are returned as base64 so attachments remain binary-safe:

```json
[
  {
    "label": "nginx/tls-cert",
    "entryPath": "infra/prod/nginx",
    "content": "attachment",
    "dataBase64": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
  }
]
```

The secret-service deployment script decodes that response and writes the actual staged files itself before encryption. The CLI stays agnostic of temp file layout.

## Example

```bash
cargo run --manifest-path ./Cargo.toml -- \
  read \
  --database ~/secrets.kdbx \
  --entry-path infra/prod/etcd-ca \
  --content attachment \
  --attachment-name ca.crt \
  > /tmp/ca.crt
```

## Batch Example

```bash
cat ./requests.json | cargo run --manifest-path ./Cargo.toml -- \
  batch-read \
  --database ~/secrets.kdbx \
  > /tmp/keepass-batch.json
```

You can then decode individual payloads from the response JSON as needed.

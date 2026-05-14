use std::env;
use std::fs;
use std::fs::File;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use clap::{Args, Parser, Subcommand, ValueEnum};
use keepass::{db::Database, DatabaseKey};
use serde::{Deserialize, Serialize};

const PASSWORD_ENV_VAR: &str = "SECRET_SERVICE_KEEPASS_PASSWORD";

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
enum PasswordSource {
    PasswordFile,
    Environment,
    Prompt,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ResolvedPassword {
    value: Option<String>,
    source: PasswordSource,
}

#[derive(Parser)]
#[command(name = "secret-service-keepass")]
#[command(about = "Read password or attachment secrets from a KeePass database")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Read(SecretArgs),
    Validate(SecretArgs),
    BatchValidate(BatchArgs),
    BatchRead(BatchArgs),
}

#[derive(Copy, Clone, Debug, Deserialize, Eq, PartialEq, Serialize, ValueEnum)]
#[serde(rename_all = "lowercase")]
enum ContentKind {
    Attachment,
    Password,
}

#[derive(Args, Clone)]
struct DatabaseAccessArgs {
    #[arg(long)]
    database: PathBuf,

    #[arg(long)]
    password_file: Option<PathBuf>,

    #[arg(long)]
    keyfile: Option<PathBuf>,
}

#[derive(Args)]
struct SecretArgs {
    #[command(flatten)]
    access: DatabaseAccessArgs,

    #[arg(long)]
    entry_path: String,

    #[arg(long, value_enum, default_value_t = ContentKind::Attachment)]
    content: ContentKind,

    #[arg(long)]
    attachment_name: Option<String>,

}

#[derive(Args)]
struct BatchArgs {
    #[command(flatten)]
    access: DatabaseAccessArgs,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct SecretRequest {
    entry_path: String,
    content: ContentKind,
    attachment_name: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
struct BatchReadResponse {
    label: String,

    #[serde(rename = "entryPath")]
    entry_path: String,

    content: ContentKind,

    #[serde(rename = "dataBase64")]
    data_base64: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct BatchSecretRequest {
    #[serde(rename = "entryPath")]
    entry_path: String,

    #[serde(default = "default_content_kind")]
    content: ContentKind,

    #[serde(rename = "attachmentName", default)]
    attachment_name: Option<String>,

    #[serde(default)]
    label: Option<String>,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("ERROR: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Read(args) => {
            let database = open_database(&args.access)?;
            let bytes = resolve_secret_bytes(&database, &args.to_secret_request())?;
            io::stdout()
                .lock()
                .write_all(&bytes)
                .context("failed to write secret to stdout")?;
        }
        Command::Validate(args) => {
            let database = open_database(&args.access)?;
            let _ = resolve_secret_bytes(&database, &args.to_secret_request())?;
        }
        Command::BatchValidate(args) => {
            run_batch_validate(&args)?;
        }
        Command::BatchRead(args) => {
            run_batch_read(&args)?;
        }
    }

    Ok(())
}

fn run_batch_validate(args: &BatchArgs) -> Result<()> {
    let requests = load_batch_requests_from_stdin()?;
    let database = open_database(&args.access)?;

    for request in &requests {
        let spec = request.to_secret_request();
        let label = request.label();
        let _ = resolve_secret_bytes(&database, &spec)
            .with_context(|| format!("failed to validate batched secret '{label}'"))?;
    }

    Ok(())
}

fn run_batch_read(args: &BatchArgs) -> Result<()> {
    let requests = load_batch_requests_from_stdin()?;
    let database = open_database(&args.access)?;
    let mut responses = Vec::with_capacity(requests.len());

    for request in &requests {
        let spec = request.to_secret_request();
        let label = request.label();

        let bytes = resolve_secret_bytes(&database, &spec)
            .with_context(|| format!("failed to retrieve batched secret '{label}'"))?;
        responses.push(BatchReadResponse {
            label,
            entry_path: spec.entry_path.clone(),
            content: spec.content,
            data_base64: base64_encode(&bytes),
        });
    }

    serde_json::to_writer(io::stdout().lock(), &responses)
        .context("failed to write batch-read response JSON to stdout")?;

    Ok(())
}

fn open_database(args: &DatabaseAccessArgs) -> Result<Database> {
    let mut key = DatabaseKey::new();
    let mut auth_summary = Vec::new();

    let resolved_password = load_password(args)?;

    if let Some(password) = resolved_password.value.as_ref() {
        key = key.with_password(&password);
        auth_summary.push(format!(
            "password: {}",
            resolved_password.source.description()
        ));
    } else {
        auth_summary.push(format!(
            "password: {} (empty, so no password component is used)",
            resolved_password.source.description()
        ));
    }

    if let Some(keyfile_path) = args.keyfile.as_ref() {
        let keyfile_bytes = fs::read(keyfile_path).with_context(|| {
            format!("failed to read KeePass key file {}", keyfile_path.display())
        })?;
        let (prepared_keyfile_bytes, keyfile_hint) = prepare_keyfile_bytes(&keyfile_bytes)?;
        let mut keyfile_cursor = prepared_keyfile_bytes.as_slice();

        key = key.with_keyfile(&mut keyfile_cursor).with_context(|| {
            format!(
                "failed to parse KeePass key file {}",
                keyfile_path.display()
            )
        })?;

        auth_summary.push(format!(
            "keyfile: {} ({})",
            keyfile_path.display(),
            keyfile_hint
        ));
    }

    if key.is_empty() {
        bail!(
            "no KeePass authentication source configured; set {PASSWORD_ENV_VAR}, pass --password-file, provide --keyfile, or use an interactive terminal"
        );
    }

    let mut database_file = File::open(&args.database).with_context(|| {
        format!(
            "failed to open KeePass database {}",
            args.database.display()
        )
    })?;

    let auth_summary = auth_summary.join("; ");

    Database::open(&mut database_file, key).with_context(|| {
        format!(
            "failed to unlock KeePass database {} [{}]",
            args.database.display(),
            auth_summary
        )
    })
}

fn load_password(args: &DatabaseAccessArgs) -> Result<ResolvedPassword> {
    if let Some(password) = load_explicit_password(args)? {
        return Ok(password);
    }

    prompt_password()
}

fn load_explicit_password(args: &DatabaseAccessArgs) -> Result<Option<ResolvedPassword>> {
    if let Some(path) = args.password_file.as_ref() {
        let password = fs::read_to_string(path)
            .with_context(|| format!("failed to read password file {}", path.display()))?;
        return Ok(Some(ResolvedPassword {
            value: normalize_password(password),
            source: PasswordSource::PasswordFile,
        }));
    }

    pick_explicit_password(read_password_from_env()?, None)
}

fn read_password_from_env() -> Result<Option<String>> {
    match env::var(PASSWORD_ENV_VAR) {
        Ok(password) => Ok(Some(password)),
        Err(env::VarError::NotPresent) => Ok(None),
        Err(env::VarError::NotUnicode(_)) => {
            bail!("environment variable {PASSWORD_ENV_VAR} contains non-unicode data")
        }
    }
}

fn pick_explicit_password(
    env_password: Option<String>,
    password_file_password: Option<String>,
) -> Result<Option<ResolvedPassword>> {
    if let Some(password) = password_file_password {
        return Ok(Some(ResolvedPassword {
            value: normalize_password(password),
            source: PasswordSource::PasswordFile,
        }));
    }

    if let Some(password) = env_password {
        return Ok(Some(ResolvedPassword {
            value: normalize_password(password),
            source: PasswordSource::Environment,
        }));
    }

    Ok(None)
}

fn prompt_password() -> Result<ResolvedPassword> {
    let password = rpassword::prompt_password("KeePass password: ")
        .context("failed to read KeePass password from terminal")?;

    Ok(ResolvedPassword {
        value: normalize_password(password),
        source: PasswordSource::Prompt,
    })
}

impl SecretArgs {
    fn to_secret_request(&self) -> SecretRequest {
        SecretRequest {
            entry_path: self.entry_path.clone(),
            content: self.content,
            attachment_name: self.attachment_name.clone(),
        }
    }
}

impl BatchSecretRequest {
    fn to_secret_request(&self) -> SecretRequest {
        SecretRequest {
            entry_path: self.entry_path.clone(),
            content: self.content,
            attachment_name: self.attachment_name.clone(),
        }
    }

    fn label(&self) -> String {
        self.label
            .clone()
            .unwrap_or_else(|| normalize_display_path(&self.entry_path))
    }
}

fn default_content_kind() -> ContentKind {
    ContentKind::Attachment
}

fn load_batch_requests_from_stdin() -> Result<Vec<BatchSecretRequest>> {
    let mut content = String::new();
    io::stdin()
        .lock()
        .read_to_string(&mut content)
        .context("failed to read batch requests from stdin")?;

    parse_batch_requests(&content, "stdin")
}

fn parse_batch_requests(content: &str, source: &str) -> Result<Vec<BatchSecretRequest>> {
    let requests: Vec<BatchSecretRequest> = serde_json::from_str(content)
        .with_context(|| format!("failed to parse batch requests from {source} as JSON"))?;

    if requests.is_empty() {
        bail!("batch requests from {source} do not contain any requests");
    }

    Ok(requests)
}

fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    let mut encoded = String::with_capacity(bytes.len().div_ceil(3) * 4);

    for chunk in bytes.chunks(3) {
        let first = chunk[0];
        let second = *chunk.get(1).unwrap_or(&0);
        let third = *chunk.get(2).unwrap_or(&0);

        encoded.push(TABLE[(first >> 2) as usize] as char);
        encoded.push(TABLE[((first & 0b0000_0011) << 4 | (second >> 4)) as usize] as char);

        if chunk.len() > 1 {
            encoded.push(TABLE[((second & 0b0000_1111) << 2 | (third >> 6)) as usize] as char);
        } else {
            encoded.push('=');
        }

        if chunk.len() > 2 {
            encoded.push(TABLE[(third & 0b0011_1111) as usize] as char);
        } else {
            encoded.push('=');
        }
    }

    encoded
}

impl PasswordSource {
    fn description(self) -> &'static str {
        match self {
            PasswordSource::PasswordFile => "loaded from --password-file",
            PasswordSource::Environment => "loaded from SECRET_SERVICE_KEEPASS_PASSWORD",
            PasswordSource::Prompt => "entered interactively",
        }
    }
}

fn prepare_keyfile_bytes(bytes: &[u8]) -> Result<(Vec<u8>, &'static str)> {
    if let Some(decoded_bytes) = decode_hex_keyfile(bytes)? {
        return Ok((
            decoded_bytes,
            "64-character hex keyfile decoded to a 32-byte raw key",
        ));
    }

    Ok((bytes.to_vec(), describe_keyfile_bytes(bytes)))
}

fn describe_keyfile_bytes(bytes: &[u8]) -> &'static str {
    if bytes.len() == 32 {
        return "32-byte raw keyfile";
    }

    if looks_like_keyfile_xml(bytes) {
        return "XML keyfile";
    }

    "arbitrary file, which keepass-rs hashes with SHA-256 before use"
}

fn decode_hex_keyfile(bytes: &[u8]) -> Result<Option<Vec<u8>>> {
    let text = match std::str::from_utf8(bytes) {
        Ok(text) => text,
        Err(_) => return Ok(None),
    };

    let trimmed = text.trim_ascii();
    if trimmed.len() != 64 {
        return Ok(None);
    }

    if !trimmed.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Ok(None);
    }

    let mut decoded = Vec::with_capacity(32);
    for chunk in trimmed.as_bytes().chunks_exact(2) {
        let pair = std::str::from_utf8(chunk).expect("hex chunks are always valid utf-8");
        let value = u8::from_str_radix(pair, 16)
            .with_context(|| format!("failed to decode hex keyfile byte '{pair}'"))?;
        decoded.push(value);
    }

    Ok(Some(decoded))
}

fn looks_like_keyfile_xml(bytes: &[u8]) -> bool {
    let preview = String::from_utf8_lossy(&bytes[..bytes.len().min(512)]);
    preview.contains("<KeyFile")
}

fn normalize_password(value: String) -> Option<String> {
    let password = trim_trailing_newlines(value);

    if password.is_empty() {
        return None;
    }

    Some(password)
}

fn trim_trailing_newlines(value: String) -> String {
    value.trim_end_matches(['\n', '\r']).to_owned()
}

fn resolve_secret_bytes(database: &Database, request: &SecretRequest) -> Result<Vec<u8>> {
    let entry = resolve_entry(database, &request.entry_path)?;

    match request.content {
        ContentKind::Password => {
            let password = entry.get_password().ok_or_else(|| {
                anyhow!(
                    "entry '{}' does not contain a password field",
                    normalize_display_path(&request.entry_path)
                )
            })?;

            Ok(password.as_bytes().to_vec())
        }
        ContentKind::Attachment => {
            resolve_attachment_bytes(&entry, &request.entry_path, request.attachment_name.as_deref())
        }
    }
}

fn resolve_entry<'a>(
    database: &'a Database,
    entry_path: &str,
) -> Result<keepass::db::EntryRef<'a>> {
    let segments = split_entry_path(entry_path)?;
    let (group_segments, entry_name) = segments.split_at(segments.len() - 1);
    let entry_name = entry_name
        .first()
        .ok_or_else(|| anyhow!("entry path '{}' is missing an entry name", entry_path))?;

    let group_id = resolve_group_id(database, group_segments)?;

    let group = database.group(group_id).ok_or_else(|| {
        anyhow!(
            "KeePass group '{}' was not found",
            normalize_display_path(&group_segments.join("/"))
        )
    })?;

    let entry_id = group
        .entry_by_name(entry_name)
        .map(|entry| entry.id())
        .ok_or_else(|| {
            anyhow!(
                "KeePass entry '{}' was not found",
                normalize_display_path(entry_path)
            )
        })?;

    database.entry(entry_id).ok_or_else(|| {
        anyhow!(
            "KeePass entry '{}' was not found",
            normalize_display_path(entry_path)
        )
    })
}

fn resolve_group_id(database: &Database, group_segments: &[String]) -> Result<keepass::db::GroupId> {
    if group_segments.is_empty() {
        return Ok(database.root().id());
    }

    let root = database.root();
    let normalized_segments = strip_root_group_prefix(root.name.as_str(), group_segments);

    let mut current_group_id = root.id();
    let mut resolved_path = Vec::new();

    for segment in normalized_segments {
        let current_group = database.group(current_group_id).ok_or_else(|| {
            anyhow!(
                "KeePass group '{}' unexpectedly disappeared during traversal",
                normalize_display_path(&resolved_path.join("/"))
            )
        })?;

        let next_group_id = current_group.group_by_name(segment).map(|group| group.id()).ok_or_else(|| {
            let available_groups = sorted_child_group_names(&current_group);
            let available_groups = if available_groups.is_empty() {
                "no child groups".to_owned()
            } else {
                available_groups.join(", ")
            };

            anyhow!(
                "KeePass group '{}' was not found below '{}'; available child groups: {}",
                segment,
                if resolved_path.is_empty() {
                    display_group_name(root.name.as_str())
                } else {
                    normalize_display_path(&resolved_path.join("/"))
                },
                available_groups
            )
        })?;

        resolved_path.push(segment.to_owned());
        current_group_id = next_group_id;
    }

    Ok(current_group_id)
}

fn strip_root_group_prefix<'a>(root_name: &str, group_segments: &'a [String]) -> &'a [String] {
    if let Some((first, remaining)) = group_segments.split_first() {
        if !root_name.is_empty() && first.eq_ignore_ascii_case(root_name) {
            return remaining;
        }
    }

    group_segments
}

fn sorted_child_group_names(group: &keepass::db::GroupRef<'_>) -> Vec<String> {
    let mut names = group.groups().map(|child| child.name.clone()).collect::<Vec<_>>();
    names.sort_by_key(|name| name.to_ascii_lowercase());
    names
}

fn display_group_name(name: &str) -> String {
    if name.is_empty() {
        "<root>".to_owned()
    } else {
        name.to_owned()
    }
}

fn resolve_attachment_bytes(
    entry: &keepass::db::EntryRef<'_>,
    entry_path: &str,
    attachment_name: Option<&str>,
) -> Result<Vec<u8>> {
    let attachment = if let Some(name) = attachment_name {
        entry.attachment_by_name(name).ok_or_else(|| {
            anyhow!(
                "attachment '{}' was not found on KeePass entry '{}'",
                name,
                normalize_display_path(entry_path)
            )
        })?
    } else if entry.attachments().count() == 1 {
        entry.attachments().next().ok_or_else(|| {
            anyhow!(
                "entry '{}' has no attachments",
                normalize_display_path(entry_path)
            )
        })?
    } else if entry.attachments().next().is_none() {
        bail!(
            "entry '{}' has no attachments",
            normalize_display_path(entry_path)
        );
    } else {
        let names = sorted_attachment_names(entry);
        bail!(
            "entry '{}' has multiple attachments; specify --attachment-name ({})",
            normalize_display_path(entry_path),
            names.join(", ")
        );
    };

    Ok(attachment.get().clone())
}

fn sorted_attachment_names(entry: &keepass::db::EntryRef<'_>) -> Vec<String> {
    let mut names = entry
        .attachments_named()
        .map(|(name, _)| name.to_owned())
        .collect::<Vec<_>>();
    names.sort();
    names
}

fn split_entry_path(entry_path: &str) -> Result<Vec<String>> {
    let segments = entry_path
        .split('/')
        .filter(|segment| !segment.is_empty())
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();

    if segments.is_empty() {
        bail!("entry path must not be empty");
    }

    Ok(segments)
}

fn normalize_display_path(path: &str) -> String {
    let path = Path::new(path);
    path.components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("/")
}

#[cfg(test)]
mod tests {
    use super::base64_encode;
    use super::BatchReadResponse;
    use super::default_content_kind;
    use super::display_group_name;
    use super::decode_hex_keyfile;
    use super::describe_keyfile_bytes;
    use super::normalize_display_path;
    use super::normalize_password;
    use super::parse_batch_requests;
    use super::pick_explicit_password;
    use super::prepare_keyfile_bytes;
    use super::resolve_group_id;
    use super::split_entry_path;
    use super::strip_root_group_prefix;
    use super::BatchSecretRequest;
    use super::ContentKind;
    use super::PasswordSource;
    use super::ResolvedPassword;
    use keepass::Database;
    use std::path::PathBuf;

    #[test]
    fn split_entry_path_discards_empty_segments() {
        assert_eq!(
            split_entry_path("/infra//prod/etcd-ca/").unwrap(),
            vec!["infra", "prod", "etcd-ca"]
        );
    }

    #[test]
    fn split_entry_path_rejects_empty_input() {
        assert!(split_entry_path("///").is_err());
    }

    #[test]
    fn normalize_display_path_collapses_redundant_separators() {
        assert_eq!(normalize_display_path("infra//prod///ca"), "infra/prod/ca");
    }

    #[test]
    fn normalize_password_trims_newlines() {
        assert_eq!(
            normalize_password("secret\n".to_owned()),
            Some("secret".to_owned())
        );
    }

    #[test]
    fn normalize_password_interprets_empty_as_none() {
        assert_eq!(normalize_password("\r\n".to_owned()), None);
    }

    #[test]
    fn explicit_password_uses_env_value() {
        let password = pick_explicit_password(Some("hunter2".to_owned()), None).unwrap();

        assert_eq!(
            password,
            Some(ResolvedPassword {
                value: Some("hunter2".to_owned()),
                source: PasswordSource::Environment,
            })
        );
    }

    #[test]
    fn explicit_password_allows_empty_env_for_keyfile_only() {
        let password = pick_explicit_password(Some(String::new()), None).unwrap();

        assert_eq!(
            password,
            Some(ResolvedPassword {
                value: None,
                source: PasswordSource::Environment,
            })
        );
    }

    #[test]
    fn explicit_password_prefers_password_file() {
        let password = pick_explicit_password(
            Some("env-password".to_owned()),
            Some("file-password\n".to_owned()),
        )
        .unwrap();

        assert_eq!(
            password,
            Some(ResolvedPassword {
                value: Some("file-password".to_owned()),
                source: PasswordSource::PasswordFile,
            })
        );
    }

    #[test]
    fn explicit_password_allows_empty_password_file() {
        let password =
            pick_explicit_password(Some("env-password".to_owned()), Some("\n".to_owned())).unwrap();

        assert_eq!(
            password,
            Some(ResolvedPassword {
                value: None,
                source: PasswordSource::PasswordFile,
            })
        );
    }

    #[test]
    fn explicit_password_returns_none_when_no_source_exists() {
        assert_eq!(pick_explicit_password(None, None).unwrap(), None);
    }

    #[test]
    fn describe_keyfile_identifies_raw_32_byte_format() {
        assert_eq!(describe_keyfile_bytes(&[0_u8; 32]), "32-byte raw keyfile");
    }

    #[test]
    fn describe_keyfile_identifies_xml_format() {
        assert_eq!(
            describe_keyfile_bytes(
                br#"<?xml version="1.0"?><KeyFile><Key><Data>abc</Data></Key></KeyFile>"#
            ),
            "XML keyfile"
        );
    }

    #[test]
    fn decode_hex_keyfile_accepts_64_character_hex_text() {
        let decoded =
            decode_hex_keyfile(b"c1c126ce47de0fc4fbc76c9f90cd4bdc52fc4b5162f4267fd895d538e4f96ab8")
                .unwrap();

        assert_eq!(
            decoded,
            Some(vec![
                0xc1, 0xc1, 0x26, 0xce, 0x47, 0xde, 0x0f, 0xc4, 0xfb, 0xc7, 0x6c, 0x9f, 0x90, 0xcd,
                0x4b, 0xdc, 0x52, 0xfc, 0x4b, 0x51, 0x62, 0xf4, 0x26, 0x7f, 0xd8, 0x95, 0xd5, 0x38,
                0xe4, 0xf9, 0x6a, 0xb8,
            ])
        );
    }

    #[test]
    fn decode_hex_keyfile_allows_trailing_newline() {
        let decoded = decode_hex_keyfile(
            b"c1c126ce47de0fc4fbc76c9f90cd4bdc52fc4b5162f4267fd895d538e4f96ab8\n",
        )
        .unwrap();

        assert!(decoded.is_some());
    }

    #[test]
    fn prepare_keyfile_bytes_reports_hex_text_compatibility() {
        let (decoded, description) = prepare_keyfile_bytes(
            b"c1c126ce47de0fc4fbc76c9f90cd4bdc52fc4b5162f4267fd895d538e4f96ab8",
        )
        .unwrap();

        assert_eq!(decoded.len(), 32);
        assert_eq!(
            description,
            "64-character hex keyfile decoded to a 32-byte raw key"
        );
    }

    #[test]
    fn strip_root_group_prefix_removes_matching_root_name() {
        let segments = vec!["Root".to_owned(), "Infrastructure".to_owned()];

        assert_eq!(
            strip_root_group_prefix("Root", &segments),
            &["Infrastructure".to_owned()]
        );
    }

    #[test]
    fn display_group_name_formats_empty_root() {
        assert_eq!(display_group_name(""), "<root>");
    }

    #[test]
    fn resolve_group_id_accepts_optional_root_prefix() {
        let mut database = Database::new();
        database.root_mut().name = "Root".into();
        database
            .root_mut()
            .add_group()
            .edit(|group| group.name = "Infrastructure".into());

        let without_root = resolve_group_id(&database, &["Infrastructure".to_owned()]).unwrap();
        let with_root = resolve_group_id(
            &database,
            &["Root".to_owned(), "Infrastructure".to_owned()],
        )
        .unwrap();

        assert_eq!(without_root, with_root);
    }

    #[test]
    fn default_content_kind_is_attachment() {
        assert_eq!(default_content_kind(), ContentKind::Attachment);
    }

    #[test]
    fn base64_encode_handles_binary_data() {
        assert_eq!(base64_encode(&[0x00, 0xff, 0x10]), "AP8Q");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
    }

    #[test]
    fn batch_read_response_serializes_entry_path() {
        let response = BatchReadResponse {
            label: "nginx/tls-cert".to_owned(),
            entry_path: "infra/prod/nginx".to_owned(),
            content: ContentKind::Attachment,
            data_base64: "Zm9v".to_owned(),
        };

        let json = serde_json::to_value(response).unwrap();

        assert_eq!(json["label"], "nginx/tls-cert");
        assert_eq!(json["entryPath"], "infra/prod/nginx");
        assert_eq!(json["content"], "attachment");
        assert_eq!(json["dataBase64"], "Zm9v");
    }

    #[test]
    fn load_batch_requests_parses_defaults() {
        let requests = parse_batch_requests(r#"[{"entryPath":"infra/prod/example"}]"#, "test input")
            .unwrap();

        assert_eq!(
            requests,
            vec![BatchSecretRequest {
                entry_path: "infra/prod/example".to_owned(),
                content: ContentKind::Attachment,
                attachment_name: None,
                label: None,
            }]
        );
    }

    #[test]
    fn parse_batch_requests_rejects_empty_arrays() {
        assert!(parse_batch_requests("[]", "test input").is_err());
    }
}

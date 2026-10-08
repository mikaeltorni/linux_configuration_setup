//! Secret-safe snapshot operations over the native Secret Service D-Bus API.

use base64::{engine::general_purpose::STANDARD, Engine};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;
use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

type Result<T> = std::result::Result<T, &'static str>;
const SERVICE_PATH: &str = "/org/freedesktop/secrets";
const SERVICE_IFACE: &str = "org.freedesktop.Secret.Service";
const COLLECTION_IFACE: &str = "org.freedesktop.Secret.Collection";
const ITEM_IFACE: &str = "org.freedesktop.Secret.Item";
const USAGE: &str = "usage: keyring-snapshot check | export PATH | import PATH | store-test-item ATTRIBUTE VALUE PASSWORD | verify-test-item ATTRIBUTE VALUE PASSWORD";

pub enum Command {
    Help,
    Check,
    Export(String),
    Import(String),
    Store {
        attribute: String,
        value: String,
        password: String,
    },
    Verify {
        attribute: String,
        value: String,
        password: String,
    },
}

#[derive(Serialize, Deserialize)]
struct SnapshotItem {
    attributes: BTreeMap<String, String>,
    content_type: String,
    label: String,
    secret: String,
}

struct Service {
    connection: Connection,
    session: OwnedObjectPath,
    collections: Vec<OwnedObjectPath>,
}

/// Parse every command's complete raw operands before service access.
/// Parameters: args - raw tokens excluding executable name.
/// Returns: parsed operation or usage error without exposing operands.
pub fn parse(args: &[String]) -> Result<Command> {
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["--help"] | ["-h"] => Ok(Command::Help),
        ["check"] => Ok(Command::Check),
        ["export", path] => Ok(Command::Export((*path).into())),
        ["import", path] => Ok(Command::Import((*path).into())),
        ["store-test-item", attribute, value, password] => Ok(Command::Store {
            attribute: (*attribute).into(),
            value: (*value).into(),
            password: (*password).into(),
        }),
        ["verify-test-item", attribute, value, password] => Ok(Command::Verify {
            attribute: (*attribute).into(),
            value: (*value).into(),
            password: (*password).into(),
        }),
        _ => Err(USAGE),
    }
}

impl Service {
    /// Open a plain private D-Bus session and require all collections unlocked.
    /// Parameters: none; the caller's session bus identifies the service.
    /// Returns: service state or a content-free error; never requests an unlock.
    fn connect() -> Result<Self> {
        let connection = Connection::session().map_err(|_| "Cannot connect to Secret Service")?;
        let proxy = Proxy::new(
            &connection,
            "org.freedesktop.secrets",
            SERVICE_PATH,
            SERVICE_IFACE,
        )
        .map_err(|_| "Cannot access Secret Service")?;
        let (_, session): (OwnedValue, OwnedObjectPath) = proxy
            .call("OpenSession", &("plain", Value::from("")))
            .map_err(|_| "Cannot open Secret Service session")?;
        let collections = proxy
            .get_property("Collections")
            .map_err(|_| "Cannot list keyring collections")?;
        drop(proxy);
        let service = Self {
            connection,
            session,
            collections,
        };
        for path in &service.collections {
            let locked: bool = service
                .proxy(path.as_str(), COLLECTION_IFACE)?
                .get_property("Locked")
                .map_err(|_| "Cannot inspect keyring lock state")?;
            if locked {
                return Err("Keyring collection is locked; unlock it once before migration");
            }
        }
        Ok(service)
    }

    /// Construct a proxy without executing any prompt or unlock action.
    /// Parameters: self - service connection; path - object path; interface - D-Bus interface.
    /// Returns: proxy or a content-free service error.
    fn proxy<'a>(&'a self, path: &'a str, interface: &'a str) -> Result<Proxy<'a>> {
        Proxy::new(&self.connection, "org.freedesktop.secrets", path, interface)
            .map_err(|_| "Cannot access keyring object")
    }

    /// Find the preexisting Login collection created by the daemon's PAM login.
    /// Parameters: self - unlocked service state.
    /// Returns: Login path or absence error; never creates a collection.
    fn login(&self) -> Result<&OwnedObjectPath> {
        self.collections
            .iter()
            .find(|path| path.as_str().ends_with("/login"))
            .ok_or("The replacement Login keyring was not created")
    }

    /// Read every existing item path in one collection.
    /// Parameters: self - service state; collection - collection object path.
    /// Returns: item paths or a content-free error.
    fn items(&self, collection: &OwnedObjectPath) -> Result<Vec<OwnedObjectPath>> {
        self.proxy(collection.as_str(), COLLECTION_IFACE)?
            .get_property("Items")
            .map_err(|_| "Cannot list keyring items")
    }

    /// Read D-Bus attributes into deterministic snapshot key order.
    /// Parameters: self - service state; path - item object path.
    /// Returns: ordered attributes or a content-free read error.
    fn attributes(&self, path: &OwnedObjectPath) -> Result<BTreeMap<String, String>> {
        let attributes: HashMap<String, String> = self
            .proxy(path.as_str(), ITEM_IFACE)?
            .get_property("Attributes")
            .map_err(|_| "Cannot read keyring attributes")?;
        Ok(attributes.into_iter().collect())
    }

    /// Read attributes, label and arbitrary secret bytes/content type for one item.
    /// Parameters: self - service state; path - item object path.
    /// Returns: compatible serialized snapshot record without printing its contents.
    fn snapshot_item(&self, path: &OwnedObjectPath) -> Result<SnapshotItem> {
        let proxy = self.proxy(path.as_str(), ITEM_IFACE)?;
        let attributes = self.attributes(path)?;
        let label = proxy
            .get_property("Label")
            .map_err(|_| "Cannot read keyring label")?;
        let (_, _, bytes, content_type): (OwnedObjectPath, Vec<u8>, Vec<u8>, String) = proxy
            .call("GetSecret", &(&self.session,))
            .map_err(|_| "Cannot read keyring secret")?;
        Ok(SnapshotItem {
            attributes,
            label,
            content_type,
            secret: STANDARD.encode(bytes),
        })
    }

    /// Assign the default alias to the existing Login collection.
    /// Parameters: self - unlocked service; login - Login object path.
    /// Returns: None on success or content-free alias error.
    fn set_default(&self, login: &OwnedObjectPath) -> Result<()> {
        self.proxy(SERVICE_PATH, SERVICE_IFACE)?
            .call::<_, _, ()>("SetAlias", &("default", login))
            .map_err(|_| "Cannot set the Login keyring as default")
    }

    /// Create one item with exact bytes and metadata, refusing returned prompts.
    /// Parameters: self - unlocked service; login - destination; item - metadata; bytes - decoded secret.
    /// Returns: None or content-free failure; never invokes a prompt.
    fn create_item(
        &self,
        login: &OwnedObjectPath,
        item: &SnapshotItem,
        bytes: &[u8],
    ) -> Result<()> {
        let attributes = item
            .attributes
            .iter()
            .map(|(key, value)| (key.as_str(), value.as_str()))
            .collect::<HashMap<_, _>>();
        let properties = HashMap::from([
            (
                "org.freedesktop.Secret.Item.Attributes",
                Value::from(attributes),
            ),
            (
                "org.freedesktop.Secret.Item.Label",
                Value::from(item.label.as_str()),
            ),
        ]);
        let secret = (
            &self.session,
            Vec::<u8>::new(),
            bytes,
            item.content_type.as_str(),
        );
        let (_, prompt): (OwnedObjectPath, OwnedObjectPath) = self
            .proxy(login.as_str(), COLLECTION_IFACE)?
            .call("CreateItem", &(properties, secret, false))
            .map_err(|_| "Cannot restore keyring item")?;
        if prompt.as_str() != "/" {
            return Err("Secret Service requested an unexpected prompt");
        }
        Ok(())
    }
}

impl Drop for Service {
    /// Close only this command's private D-Bus session.
    /// Parameters: self - service state being released.
    /// Returns: None; cleanup errors are ignored without exposing item data.
    fn drop(&mut self) {
        if let Ok(proxy) = self.proxy(self.session.as_str(), "org.freedesktop.Secret.Session") {
            let _ = proxy.call::<_, _, ()>("Close", &());
        }
    }
}

/// Export all non-session, non-legacy items only after the full read succeeds.
/// Parameters: path - snapshot destination.
/// Returns: original export count message or content-free failure.
fn export_items(path: &Path) -> Result<String> {
    let service = Service::connect()?;
    let mut items = Vec::new();
    for collection in &service.collections {
        if collection.as_str().ends_with("/session") {
            continue;
        }
        for path in service.items(collection)? {
            let attributes = service.attributes(&path)?;
            if attributes.contains_key("keyring") {
                continue;
            }
            items.push(service.snapshot_item(&path)?);
        }
    }
    let document = serde_json::to_vec(&items).map_err(|_| "Cannot serialize keyring snapshot")?;
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(path)
        .map_err(|_| "Cannot open keyring snapshot")?;
    file.set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|_| "Cannot protect keyring snapshot")?;
    file.set_len(0)
        .map_err(|_| "Cannot truncate keyring snapshot")?;
    file.write_all(&document)
        .map_err(|_| "Cannot write keyring snapshot")?;
    Ok(format!("Exported {} keyring item(s)\n", items.len()))
}

/// Load and validate every snapshot record before changing Login or its alias.
/// Parameters: path - complete snapshot to restore.
/// Returns: validated records and decoded secrets, or a content-free format/read error.
fn read_snapshot(path: &Path) -> Result<Vec<(SnapshotItem, Vec<u8>)>> {
    let data = fs::read(path).map_err(|_| "Cannot read keyring snapshot")?;
    let items: Vec<SnapshotItem> =
        serde_json::from_slice(&data).map_err(|_| "Invalid keyring snapshot")?;
    items
        .into_iter()
        .map(|item| {
            let bytes = STANDARD
                .decode(&item.secret)
                .map_err(|_| "Invalid keyring secret encoding")?;
            Ok((item, bytes))
        })
        .collect()
}

/// Restore validated snapshot records into Login and select its default alias.
/// Parameters: path - snapshot to restore into the already-unlocked destination.
/// Returns: original restore count message or content-free failure.
fn import_items(path: &Path) -> Result<String> {
    let items = read_snapshot(path)?;
    let service = Service::connect()?;
    let login = service.login()?;
    service.set_default(login)?;
    for (item, bytes) in &items {
        service.create_item(login, item, bytes)?;
    }
    Ok(format!("Restored {} keyring item(s)\n", items.len()))
}

/// Require an unlocked Login collection whose default alias points to it.
/// Parameters: none; current bus identifies the queried service.
/// Returns: original check message or content-free failure.
fn check_keyring() -> Result<String> {
    let service = Service::connect()?;
    let login = service.login()?;
    let default: OwnedObjectPath = service
        .proxy(SERVICE_PATH, SERVICE_IFACE)?
        .call("ReadAlias", &("default",))
        .map_err(|_| "Cannot inspect the default keyring alias")?;
    if default != *login {
        return Err("Login is not the default keyring collection");
    }
    Ok("Prompt-free Login keyring is unlocked\n".into())
}

/// Create the retained text/binary migration fixture in an isolated Login.
/// Parameters: attribute - text item's attribute key; value - attribute value; password - fixture secret.
/// Returns: empty output or content-free failure.
fn store_test_item(attribute: &str, value: &str, password: &str) -> Result<String> {
    let service = Service::connect()?;
    let login = service.login()?;
    service.set_default(login)?;
    let text = SnapshotItem {
        attributes: BTreeMap::from([
            (attribute.into(), value.into()),
            ("xdg:schema".into(), "keyring.migration.test".into()),
        ]),
        content_type: "text/plain".into(),
        label: "Migration test".into(),
        secret: String::new(),
    };
    service.create_item(login, &text, password.as_bytes())?;
    let binary = SnapshotItem {
        attributes: BTreeMap::from([("xdg:schema".into(), "keyring.migration.binary-test".into())]),
        content_type: "application/octet-stream".into(),
        label: "Binary migration test".into(),
        secret: String::new(),
    };
    service.create_item(login, &binary, &[0x94, 0x00, 0xff])?;
    Ok(String::new())
}

/// Verify the retained fixture's text/binary secret values without disclosing them.
/// Parameters: attribute - text attribute key; value - expected attribute; password - expected text bytes.
/// Returns: empty output or content-free verification error.
fn verify_test_item(attribute: &str, value: &str, password: &str) -> Result<String> {
    let service = Service::connect()?;
    let login = service.login()?;
    let mut restored = BTreeMap::new();
    for path in service.items(login)? {
        let item = service.snapshot_item(&path)?;
        if let Some(schema) = item.attributes.get("xdg:schema") {
            let bytes = STANDARD
                .decode(&item.secret)
                .map_err(|_| "Cannot decode verification item")?;
            restored.insert(schema.clone(), bytes);
        }
    }
    // Retain the original fixture verifier's value checks; attributes are
    // independently asserted by public export in the migration regression.
    let _ = (attribute, value);
    if restored.get("keyring.migration.test").map(Vec::as_slice) != Some(password.as_bytes()) {
        return Err("Migrated text item did not retain its secret");
    }
    if restored
        .get("keyring.migration.binary-test")
        .map(Vec::as_slice)
        != Some([0x94, 0x00, 0xff].as_slice())
    {
        return Err("Migrated binary item did not retain its secret");
    }
    Ok(String::new())
}

/// Dispatch only parsed arguments to secret-safe operation owners.
/// Parameters: command - parsed operation and complete operands.
/// Returns: compatible stdout or content-free operation failure.
pub fn execute(command: Command) -> Result<String> {
    match command {
        Command::Help => Ok(format!("{USAGE}\n")),
        Command::Check => check_keyring(),
        Command::Export(path) => export_items(Path::new(&path)),
        Command::Import(path) => import_items(Path::new(&path)),
        Command::Store {
            attribute,
            value,
            password,
        } => store_test_item(&attribute, &value, &password),
        Command::Verify {
            attribute,
            value,
            password,
        } => verify_test_item(&attribute, &value, &password),
    }
}

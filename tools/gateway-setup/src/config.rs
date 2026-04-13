use serde::Deserialize;
use std::fs;
use std::io;

#[derive(Debug, Deserialize, Clone)]
pub struct GatewayConfig {
    pub hostname: Option<String>,
    pub domain: Option<String>,
    pub profile: Option<String>,
    #[serde(default)]
    pub network: NetworkConfig,
    #[serde(default)]
    pub dhcp: DhcpConfig,
    #[serde(default)]
    pub hosts: Vec<Host>,
    pub wifi: Option<std::collections::HashMap<String, WifiRadio>>,
}

impl GatewayConfig {
    pub fn load(path: &str) -> io::Result<Self> {
        let content = fs::read_to_string(path)?;
        toml::from_str(&content)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
    }

    pub fn domain(&self) -> String {
        self.domain.clone().unwrap_or_else(|| "lan.local".to_string())
    }
}

impl Default for GatewayConfig {
    fn default() -> Self {
        GatewayConfig {
            hostname: Some("gw".to_string()),
            domain: Some("lan.local".to_string()),
            profile: Some("alix-networkd".to_string()),
            network: NetworkConfig::default(),
            dhcp: DhcpConfig::default(),
            hosts: vec![],
            wifi: None,
        }
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct NetworkConfig {
    #[serde(default = "default_wan")]
    pub wan_interface: String,
    #[serde(default = "default_lan")]
    pub lan_interface: String,
    #[serde(default = "default_lan_ip")]
    pub lan_ipv4: String,
    #[serde(default)]
    pub lan_prefix_len: u8,
    #[serde(default)]
    pub ipv6_prefix: String,
}

impl Default for NetworkConfig {
    fn default() -> Self {
        NetworkConfig {
            wan_interface: default_wan(),
            lan_interface: default_lan(),
            lan_ipv4: default_lan_ip(),
            lan_prefix_len: 24,
            ipv6_prefix: String::new(),
        }
    }
}

fn default_wan() -> String { "eth0".to_string() }
fn default_lan() -> String { "eth1".to_string() }
fn default_lan_ip() -> String { "192.168.1.1".to_string() }

#[derive(Debug, Deserialize, Clone)]
pub struct DhcpConfig {
    #[serde(default = "default_range_start")]
    pub range_start: String,
    #[serde(default = "default_range_end")]
    pub range_end: String,
}

impl Default for DhcpConfig {
    fn default() -> Self {
        DhcpConfig {
            range_start: default_range_start(),
            range_end: default_range_end(),
        }
    }
}

fn default_range_start() -> String { "192.168.1.100".to_string() }
fn default_range_end() -> String { "192.168.1.200".to_string() }

#[derive(Debug, Deserialize, Clone)]
pub struct Host {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub mac: String,
    #[serde(default)]
    pub ip: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct WifiRadio {
    #[serde(default = "default_band")]
    pub band: String,
    #[serde(default = "default_channel")]
    pub channel: u32,
    #[serde(default = "default_ssid")]
    pub ssid: String,
    pub passphrase: Option<String>,
    #[serde(default)]
    pub hidden: bool,
}

fn default_band() -> String { "2.4".to_string() }
fn default_channel() -> u32 { 6 }
fn default_ssid() -> String { "Gateway".to_string() }

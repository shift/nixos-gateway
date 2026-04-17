use std::fs;
use std::io;

#[derive(Debug, Clone)]
pub struct Config {
    pub check_interval_secs: u64,
    pub ping_target: String,
    pub wan_interface: String,
    pub dns_test_domain: String,
    pub dns_server: String,
    pub services: Vec<String>,
    pub monitored_interfaces: Vec<String>,
}

impl Config {
    pub fn load(path: &str) -> io::Result<Self> {
        let content = fs::read_to_string(path)?;
        let value: toml::Value = content
            .parse()
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

        let default = Self::default();

        Ok(Config {
            check_interval_secs: value
                .get("check_interval_secs")
                .and_then(|v| v.as_integer())
                .unwrap_or(default.check_interval_secs as i64) as u64,
            ping_target: value
                .get("ping_target")
                .and_then(|v| v.as_str())
                .unwrap_or(&default.ping_target)
                .to_string(),
            wan_interface: value
                .get("wan_interface")
                .and_then(|v| v.as_str())
                .unwrap_or(&default.wan_interface)
                .to_string(),
            dns_test_domain: value
                .get("dns_test_domain")
                .and_then(|v| v.as_str())
                .unwrap_or(&default.dns_test_domain)
                .to_string(),
            dns_server: value
                .get("dns_server")
                .and_then(|v| v.as_str())
                .unwrap_or(&default.dns_server)
                .to_string(),
            services: value
                .get("services")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or(default.services),
            monitored_interfaces: value
                .get("monitored_interfaces")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or(default.monitored_interfaces),
        })
    }
}

impl Default for Config {
    fn default() -> Self {
        Config {
            check_interval_secs: 30,
            ping_target: "1.1.1.1".to_string(),
            wan_interface: "eth0".to_string(),
            dns_test_domain: "one.one.one.one".to_string(),
            dns_server: "127.0.0.1".to_string(),
            services: vec![
                "systemd-networkd.service".into(),
                "hostapd-wlan0.service".into(),
                "hostapd-wlan1.service".into(),
                "sshd.service".into(),
            ],
            monitored_interfaces: vec![
                "eth0".into(),
                "eth1".into(),
                "wlan0".into(),
                "wlan1".into(),
            ],
        }
    }
}

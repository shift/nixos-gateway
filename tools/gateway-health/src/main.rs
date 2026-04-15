mod config;
mod stats;

use config::Config;
use stats::HealthReport;
use std::fs;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use zbus::{dbus_interface, ConnectionBuilder};

struct HealthService {
    config: Config,
    last_report: Arc<Mutex<Option<HealthReport>>>,
}

#[dbus_interface(name = "org.gateway.Health")]
impl HealthService {
    async fn check(&self) -> zbus::fdo::Result<String> {
        let report = self.run_checks().await;
        let is_healthy = report.healthy;
        let json = serde_json::to_string_pretty(&report)
            .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))?;
        let mut last = self.last_report.lock().await;
        let changed = match &*last {
            Some(prev) => prev.healthy != is_healthy,
            None => true,
        };
        *last = Some(report);
        if changed { eprintln!("health changed to {}", is_healthy); }
        Ok(json)
    }

    async fn get_stats(&self) -> zbus::fdo::Result<String> {
        let last = self.last_report.lock().await;
        match &*last {
            Some(r) => serde_json::to_string_pretty(r).map_err(|e| zbus::fdo::Error::Failed(e.to_string())),
            None => Err(zbus::fdo::Error::Failed("No report yet".into())),
        }
    }

    async fn is_healthy(&self) -> zbus::fdo::Result<bool> {
        Ok(self.last_report.lock().await.as_ref().map(|r| r.healthy).unwrap_or(false))
    }

    async fn service_failed(&self, unit: &str) -> zbus::fdo::Result<()> {
        eprintln!("WARN: service failed: {}", unit);
        *self.last_report.lock().await = Some(self.run_checks().await);
        Ok(())
    }

    async fn link_changed(&self, iface: &str, state: &str) -> zbus::fdo::Result<()> {
        eprintln!("INFO: link {} -> {}", iface, state);
        if state != "up" && iface == self.config.wan_interface {
            *self.last_report.lock().await = Some(self.run_checks().await);
        }
        Ok(())
    }
}

impl HealthService {
    async fn run_checks(&self) -> HealthReport {
        let mut report = HealthReport::new();
        report.ping_upstream = stats::check_carrier(&self.config.wan_interface);
        report.dns_resolution = stats::dns_resolve(
            &self.config.dns_test_domain, &self.config.dns_server, Duration::from_secs(3)
        ).await;
        report.services = stats::check_services(&self.config.services);
        report.conntrack = stats::read_conntrack_count();
        report.conntrack_max = stats::read_conntrack_max();
        report.interfaces = stats::read_interface_stats(&self.config.monitored_interfaces);
        report.memory = stats::read_memory_info();
        report.zram = stats::read_zram_info();
        report.healthy = report.ping_upstream.unwrap_or(false) || report.dns_resolution.unwrap_or(false);
        if let Ok(json) = serde_json::to_string_pretty(&report) {
            let _ = fs::write("/run/gateway/stats.json", &json);
            let _ = fs::write("/run/gateway/healthy", if report.healthy { "1" } else { "0" });
        }
        report
    }
}

#[tokio::main]
async fn main() -> zbus::Result<()> {
    let config = Config::load("/etc/gateway/health.toml").unwrap_or_else(|_| Config::default());
    let check_interval = config.check_interval_secs;
    let last_report: Arc<Mutex<Option<HealthReport>>> = Arc::new(Mutex::new(None));
    let service = HealthService { config, last_report: last_report.clone() };

    let _conn = ConnectionBuilder::system()?
        .name("org.gateway.Health")?
        .serve_at("/org/gateway/Health", service)?
        .build().await?;

    eprintln!("gateway-health: D-Bus service started");

    if let Ok(sock) = std::env::var("NOTIFY_SOCKET") {
        if let Ok(s) = std::os::unix::net::UnixDatagram::unbound() { let _ = s.send_to(b"READY=1", &sock); }
    }

    let periodic = last_report;
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(Duration::from_secs(check_interval));
        loop {
            tick.tick().await;
            let report = stats::quick_health_check();
            let mut last = periodic.lock().await;
            let changed = match &*last { Some(p) => p.healthy != report.healthy, None => true };
            *last = Some(report);
            if changed { eprintln!("health state changed"); }
        }
    });

    loop { tokio::time::sleep(Duration::from_secs(3600)).await; }
}

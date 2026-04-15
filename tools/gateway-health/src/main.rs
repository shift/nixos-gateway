mod config;
mod stats;

use config::Config;
use stats::HealthReport;
use std::fs;
use std::time::Duration;

fn main() {
    let config = Config::load("/etc/gateway/health.toml")
        .unwrap_or_else(|_| Config::default());

    let check_interval = config.check_interval_secs;

    eprintln!("gateway-health: starting (check interval: {}s)", check_interval);

    // Notify systemd we're ready
    if let Ok(sock_path) = std::env::var("NOTIFY_SOCKET") {
        if let Ok(socket) = std::os::unix::net::UnixDatagram::unbound() {
            let _ = socket.send_to(b"READY=1", &sock_path);
        }
    }

    // Ensure output directory exists
    let _ = fs::create_dir_all("/run/gateway");

    // Periodic health check loop
    loop {
        std::thread::sleep(Duration::from_secs(check_interval));

        let report = run_checks(&config);

        // Write JSON to tmpfs for SSH-based retrieval
        if let Ok(json) = serde_json::to_string_pretty(&report) {
            let _ = fs::write("/run/gateway/stats.json", &json);
            let _ = fs::write("/run/gateway/healthy", if report.healthy { "1" } else { "0" });
        }

        if !report.healthy {
            eprintln!("WARN: gateway unhealthy");
        }
    }
}

fn run_checks(config: &Config) -> HealthReport {
    let mut report = HealthReport::new();

    report.ping_upstream = stats::check_carrier(&config.wan_interface);
    report.services = stats::check_services(&config.services);
    report.conntrack = stats::read_conntrack_count();
    report.conntrack_max = stats::read_conntrack_max();
    report.interfaces = stats::read_interface_stats(&config.monitored_interfaces);
    report.memory = stats::read_memory_info();
    report.zram = stats::read_zram_info();

    report.healthy = report.ping_upstream.unwrap_or(false);

    report
}

use serde::Serialize;
use std::fs;
use std::net::UdpSocket;
use std::time::Duration;

#[derive(Debug, Clone, Serialize)]
pub struct HealthReport {
    pub healthy: bool,
    pub ping_upstream: Option<bool>,
    pub dns_resolution: Option<bool>,
    pub services: Vec<ServiceStatus>,
    pub conntrack: Option<u64>,
    pub conntrack_max: Option<u64>,
    pub interfaces: Vec<InterfaceStats>,
    pub memory: Option<MemoryInfo>,
    pub zram: Option<ZramInfo>,
}

impl HealthReport {
    pub fn new() -> Self {
        HealthReport {
            healthy: false,
            ping_upstream: None,
            dns_resolution: None,
            services: Vec::new(),
            conntrack: None,
            conntrack_max: None,
            interfaces: Vec::new(),
            memory: None,
            zram: None,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct ServiceStatus {
    pub name: String,
    pub active: bool,
    pub state: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct InterfaceStats {
    pub name: String,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub rx_packets: u64,
    pub tx_packets: u64,
    pub carrier: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct MemoryInfo {
    pub total_kb: u64,
    pub available_kb: u64,
    pub used_kb: u64,
    pub buffers_kb: u64,
    pub cached_kb: u64,
    pub swap_total_kb: u64,
    pub swap_used_kb: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct ZramInfo {
    pub disksize_kb: u64,
    pub compr_data_size_kb: u64,
    pub mem_used_total_kb: u64,
    pub orig_data_size_kb: u64,
}

// ── In-process checks (no child processes, no allocations on hot paths) ──

/// Check if interface has carrier — reads /sys/class/net/<iface>/carrier
pub fn check_carrier(interface: &str) -> Option<bool> {
    let carrier = fs::read_to_string(format!("/sys/class/net/{}/carrier", interface)).ok()?;
    Some(carrier.trim() == "1")
}

/// Resolve a hostname via a single UDP DNS query.
/// Returns Some(true) on NOERROR, Some(false) on error response, None on timeout/failure.
pub fn dns_resolve(domain: &str, dns_server: &str, timeout: Duration) -> Option<bool> {
    // Build DNS query packet
    let mut query = Vec::with_capacity(domain.len() + 20);

    // Header
    query.extend_from_slice(&[0x12, 0x34]); // ID
    query.extend_from_slice(&[0x01, 0x00]); // Flags: RD
    query.extend_from_slice(&[0x00, 0x01]); // QDCOUNT: 1
    query.extend_from_slice(&[0x00, 0x00]); // ANCOUNT
    query.extend_from_slice(&[0x00, 0x00]); // NSCOUNT
    query.extend_from_slice(&[0x00, 0x00]); // ARCOUNT

    // QNAME
    for label in domain.split('.') {
        query.push(label.len() as u8);
        query.extend_from_slice(label.as_bytes());
    }
    query.push(0x00);

    // QTYPE=A, QCLASS=IN
    query.extend_from_slice(&[0x00, 0x01, 0x00, 0x01]);

    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.set_read_timeout(Some(timeout)).ok()?;
    socket.connect((dns_server, 53)).ok()?;
    socket.send(&query).ok()?;

    let mut response = [0u8; 512];
    let len = socket.recv(&mut response).ok()?;

    if len >= 4 {
        Some((response[3] & 0x0f) == 0) // rcode == NOERROR
    } else {
        None
    }
}

/// Check services by reading cgroup membership — no systemctl fork
pub fn check_services(services: &[String]) -> Vec<ServiceStatus> {
    services
        .iter()
        .filter_map(|svc| {
            let state = read_unit_state(svc);
            Some(ServiceStatus {
                name: svc.clone(),
                active: state == "active",
                state,
            })
        })
        .collect()
}

fn read_unit_state(unit: &str) -> String {
    // Try unified cgroup first, then legacy
    for path in &[
        format!("/sys/fs/cgroup/system.slice/{}/cgroup.procs", unit),
        format!("/sys/fs/cgroup/systemd/system.slice/{}/cgroup.procs", unit),
    ] {
        if let Ok(procs) = fs::read_to_string(path) {
            return if procs.lines().any(|l| !l.trim().is_empty()) {
                "active".to_string()
            } else {
                "inactive".to_string()
            };
        }
    }
    "unknown".to_string()
}

// ── Stats readers (all /proc and /sys, zero child processes) ──

pub fn read_conntrack_count() -> Option<u64> {
    read_proc_u64("/proc/sys/net/netfilter/nf_conntrack_count")
}

pub fn read_conntrack_max() -> Option<u64> {
    read_proc_u64("/proc/sys/net/netfilter/nf_conntrack_max")
}

pub fn read_interface_stats(interfaces: &[String]) -> Vec<InterfaceStats> {
    interfaces
        .iter()
        .filter_map(|name| {
            let base = format!("/sys/class/net/{}/statistics/", name);
            Some(InterfaceStats {
                name: name.clone(),
                rx_bytes: read_sys_u64(&format!("{}rx_bytes", &base))?,
                tx_bytes: read_sys_u64(&format!("{}tx_bytes", &base))?,
                rx_packets: read_sys_u64(&format!("{}rx_packets", &base))?,
                tx_packets: read_sys_u64(&format!("{}tx_packets", &base))?,
                carrier: fs::read_to_string(format!("/sys/class/net/{}/carrier", name))
                    .ok()
                    .map(|s| s.trim() == "1")
                    .unwrap_or(false),
            })
        })
        .collect()
}

pub fn read_memory_info() -> Option<MemoryInfo> {
    let content = fs::read_to_string("/proc/meminfo").ok()?;
    let mut info = MemoryInfo {
        total_kb: 0,
        available_kb: 0,
        used_kb: 0,
        buffers_kb: 0,
        cached_kb: 0,
        swap_total_kb: 0,
        swap_used_kb: 0,
    };

    for line in content.lines() {
        let mut parts = line.split_whitespace();
        let key = parts.next()?;
        let val: u64 = parts.next()?.parse().unwrap_or(0);

        match key {
            "MemTotal:" => info.total_kb = val,
            "MemAvailable:" => info.available_kb = val,
            "Buffers:" => info.buffers_kb = val,
            "Cached:" => info.cached_kb = val,
            "SwapTotal:" => info.swap_total_kb = val,
            "SwapFree:" => info.swap_used_kb = info.swap_total_kb.saturating_sub(val),
            _ => {}
        }
    }
    info.used_kb = info.total_kb.saturating_sub(info.available_kb);
    Some(info)
}

pub fn read_zram_info() -> Option<ZramInfo> {
    let mm_stat = fs::read_to_string("/sys/block/zram0/mm_stat").ok()?;
    let parts: Vec<u64> = mm_stat
        .split_whitespace()
        .filter_map(|s| s.parse().ok())
        .collect();

    if parts.len() >= 3 {
        Some(ZramInfo {
            orig_data_size_kb: parts[0] / 1024,
            compr_data_size_kb: parts[1] / 1024,
            mem_used_total_kb: parts[2] / 1024,
            disksize_kb: fs::read_to_string("/sys/block/zram0/disksize")
                .ok()
                .and_then(|s| s.trim().parse::<u64>().ok())
                .unwrap_or(0)
                / 1024,
        })
    } else {
        None
    }
}

/// Quick periodic check — just the essentials, no heavy stats
pub fn quick_health_check() -> HealthReport {
    let mut report = HealthReport::new();

    // Just check carrier + DNS — the two most critical indicators
    report.ping_upstream = check_carrier("eth0");
    report.dns_resolution = None; // Skip DNS on periodic, D-Bus callers can trigger full check
    report.memory = read_memory_info();
    report.conntrack = read_conntrack_count();
    report.conntrack_max = read_conntrack_max();

    report.healthy = report.ping_upstream.unwrap_or(false);

    // Persist to tmpfs
    if let Ok(json) = serde_json::to_string_pretty(&report) {
        let _ = fs::write("/run/gateway/stats.json", &json);
    }

    report
}

fn read_proc_u64(path: &str) -> Option<u64> {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| s.trim().parse().ok())
}

fn read_sys_u64(path: &str) -> Option<u64> {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| s.trim().parse().ok())
}

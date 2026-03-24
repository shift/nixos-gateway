{ }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "simulator-web-interface";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    nodejs
    npm
  ];

  installPhase = ''
    mkdir -p $out/share/simulator-web

    # Create comprehensive HTML interface
    cat > $out/share/simulator-web/index.html << 'EOF'
    <!DOCTYPE html>
    <html>
    <head>
        <title>Interactive VM Simulator - Human Verification</title>
        <style>
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                margin: 0;
                padding: 20px;
                background-color: #f5f5f5;
            }
            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 20px;
                border-radius: 8px;
                margin-bottom: 20px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            .container {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 20px;
                margin-bottom: 20px;
            }
            .panel {
                background: white;
                border-radius: 8px;
                padding: 20px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            .vm-card {
                border: 2px solid #e0e0e0;
                border-radius: 8px;
                padding: 15px;
                margin: 10px 0;
                transition: all 0.3s ease;
            }
            .vm-card.running {
                border-color: #28a745;
                background-color: #d4edda;
            }
            .vm-card.stopped {
                border-color: #dc3545;
                background-color: #f8d7da;
            }
            .vm-card.starting {
                border-color: #ffc107;
                background-color: #fff3cd;
            }
            .feature-list {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 10px;
            }
            .feature-item {
                padding: 10px;
                border: 1px solid #ddd;
                border-radius: 4px;
                background: #f9f9f9;
                cursor: pointer;
                transition: background-color 0.3s;
            }
            .feature-item:hover {
                background: #e9ecef;
            }
            .feature-item.selected {
                background: #007bff;
                color: white;
                border-color: #007bff;
            }
            .checklist-item {
                display: flex;
                align-items: center;
                margin: 8px 0;
                padding: 8px;
                background: #f8f9fa;
                border-radius: 4px;
            }
            .checklist-item.completed {
                background: #d4edda;
                text-decoration: line-through;
            }
            .btn {
                padding: 8px 16px;
                border: none;
                border-radius: 4px;
                cursor: pointer;
                margin: 5px;
                transition: background-color 0.3s;
            }
            .btn-primary { background: #007bff; color: white; }
            .btn-success { background: #28a745; color: white; }
            .btn-danger { background: #dc3545; color: white; }
            .btn-warning { background: #ffc107; color: black; }
            .btn:hover { opacity: 0.8; }
            .status-indicator {
                display: inline-block;
                width: 12px;
                height: 12px;
                border-radius: 50%;
                margin-right: 8px;
            }
            .status-running { background: #28a745; }
            .status-stopped { background: #dc3545; }
            .status-starting { background: #ffc107; }
            .logs {
                background: #f8f9fa;
                border: 1px solid #dee2e6;
                border-radius: 4px;
                padding: 10px;
                height: 200px;
                overflow-y: auto;
                font-family: monospace;
                font-size: 12px;
            }
            .evidence-panel {
                background: #f8f9fa;
                border: 1px solid #dee2e6;
                border-radius: 4px;
                padding: 15px;
                margin-top: 10px;
            }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>🖥️ Interactive VM Simulator</h1>
            <p>Human Verification & Signoff Platform</p>
        </div>

        <div class="container">
            <div class="panel">
                <h2>🚀 VM Instances</h2>
                <div id="vm-list">
                    <p>Loading VMs...</p>
                </div>
                <div class="logs" id="vm-logs">
                    VM operation logs will appear here...
                </div>
            </div>

            <div class="panel">
                <h2>⚙️ Feature Selection</h2>
                <div class="feature-list" id="feature-list">
                    <div class="feature-item" data-feature="networking">🌐 Networking</div>
                    <div class="feature-item" data-feature="security">🔒 Security</div>
                    <div class="feature-item" data-feature="monitoring">📊 Monitoring</div>
                    <div class="feature-item" data-feature="routing">🚦 Routing</div>
                    <div class="feature-item" data-feature="vpn">🔗 VPN</div>
                    <div class="feature-item" data-feature="qos">⚡ QoS</div>
                </div>
                <button class="btn btn-primary" onclick="configureVM()">Apply Configuration</button>
            </div>
        </div>

        <div class="container">
            <div class="panel">
                <h2>✅ Verification Checklist</h2>
                <div id="checklist">
                    <p>Select features above to load verification checklist...</p>
                </div>
            </div>

            <div class="panel">
                <h2>📸 Evidence Collection</h2>
                <div class="evidence-panel">
                    <button class="btn btn-success" onclick="captureScreenshot()">📷 Capture Screenshot</button>
                    <button class="btn btn-primary" onclick="collectLogs()">📄 Collect Logs</button>
                    <button class="btn btn-warning" onclick="runTests()">🧪 Run Automated Tests</button>
                    <div id="evidence-list">
                        <p>No evidence collected yet...</p>
                    </div>
                </div>
            </div>
        </div>

        <div class="panel">
            <h2>✍️ Human Signoff</h2>
            <div style="margin-bottom: 15px;">
                <label>Reviewer Name:</label>
                <input type="text" id="reviewer-name" placeholder="Enter your name" style="margin-left: 10px; padding: 5px;">
            </div>
            <div style="margin-bottom: 15px;">
                <label>Verification Notes:</label>
                <textarea id="verification-notes" rows="3" placeholder="Enter any observations or notes..." style="width: 100%; padding: 5px;"></textarea>
            </div>
            <button class="btn btn-success" onclick="submitSignoff()" style="font-size: 16px; padding: 12px 24px;">
                ✅ Submit Human Signoff
            </button>
            <div id="signoff-status" style="margin-top: 10px;"></div>
        </div>

        <div class="panel">
            <h2>Signoff Management</h2>
            <button class="btn btn-primary" onclick="loadSignoffs()">Load Signoffs</button>
            <div id="signoff-list" style="margin-top: 15px;">
                <p>Click "Load Signoffs" to view pending approvals...</p>
            </div>
        </div>

        <script>
            let selectedFeatures = [];
            let currentChecklist = [];

            async function loadVMs() {
                try {
                    const response = await fetch('/api/vms');
                    const vms = await response.json();
                    const vmContainer = document.getElementById('vm-list');

                    if (vms.length === 0) {
                        vmContainer.innerHTML = '<p>No VMs running. Click "Start VM" to begin.</p>';
                        return;
                    }

                    vmContainer.innerHTML = vms.map(vm => `
                        <div class="vm-card ${vm.status}">
                            <h3>
                                <span class="status-indicator status-${vm.status}"></span>
                                ${vm.name}
                            </h3>
                            <p><strong>Status:</strong> ${vm.status.toUpperCase()}</p>
                            <p><strong>IP:</strong> ${vm.ip || 'Assigning...'}</p>
                            <p><strong>Features:</strong> ${vm.features ? vm.features.join(', ') : 'None'}</p>
                            <div style="margin-top: 10px;">
                                <button class="btn btn-success" onclick="startVM('${vm.name}')">▶️ Start</button>
                                <button class="btn btn-danger" onclick="stopVM('${vm.name}')">⏹️ Stop</button>
                                <button class="btn btn-warning" onclick="resetVM('${vm.name}')">🔄 Reset</button>
                                <button class="btn btn-primary" onclick="connectVM('${vm.name}')">🔗 Connect</button>
                            </div>
                        </div>
                    `).join('');
                } catch (error) {
                    console.error('Failed to load VMs:', error);
                    document.getElementById('vm-list').innerHTML = '<p>Error loading VMs. Check console for details.</p>';
                }
            }

            async function startVM(name) {
                try {
                    await fetch(`/api/vms/${name}/start`, { method: 'POST' });
                    logVMAction(`Starting VM: ${name}`);
                    loadVMs();
                } catch (error) {
                    logVMAction(`Failed to start VM ${name}: ${error.message}`);
                }
            }

            async function stopVM(name) {
                try {
                    await fetch(`/api/vms/${name}/stop`, { method: 'POST' });
                    logVMAction(`Stopping VM: ${name}`);
                    loadVMs();
                } catch (error) {
                    logVMAction(`Failed to stop VM ${name}: ${error.message}`);
                }
            }

            async function resetVM(name) {
                try {
                    await fetch(`/api/vms/${name}/reset`, { method: 'POST' });
                    logVMAction(`Resetting VM: ${name}`);
                    loadVMs();
                } catch (error) {
                    logVMAction(`Failed to reset VM ${name}: ${error.message}`);
                }
            }

            function connectVM(name) {
                window.open(`/connect/${name}`, '_blank');
            }

            function logVMAction(message) {
                const logs = document.getElementById('vm-logs');
                const timestamp = new Date().toLocaleTimeString();
                logs.innerHTML += `[${timestamp}] ${message}\n`;
                logs.scrollTop = logs.scrollHeight;
            }

            // Verification scenarios data (would be loaded from Nix config)
            const verificationScenarios = {
                networking: {
                    dhcp: {
                        title: "DHCP Server Functionality",
                        steps: [
                            "Check DHCP service is running",
                            "Verify DHCP configuration is loaded",
                            "Test IP address assignment to clients",
                            "Validate lease database updates",
                            "Check DNS updates from DHCP"
                        ]
                    },
                    dns: {
                        title: "DNS Resolution",
                        steps: [
                            "Check DNS service is running",
                            "Test forward DNS resolution",
                            "Test reverse DNS resolution",
                            "Verify DNS caching works",
                            "Check DNSSEC validation"
                        ]
                    },
                    routing: {
                        title: "Network Routing",
                        steps: [
                            "Check routing table entries",
                            "Test static route configuration",
                            "Verify IP forwarding is enabled",
                            "Test inter-network connectivity",
                            "Check routing protocol convergence"
                        ]
                    }
                },
                security: {
                    firewall: {
                        title: "Firewall Rules",
                        steps: [
                            "Check firewall service is running",
                            "Verify rule loading",
                            "Test allowed traffic passes",
                            "Test blocked traffic is dropped",
                            "Check logging of blocked attempts"
                        ]
                    },
                    vpn: {
                        title: "VPN Connectivity",
                        steps: [
                            "Check VPN service configuration",
                            "Test tunnel establishment",
                            "Verify encrypted traffic flow",
                            "Check certificate validation",
                            "Test VPN client connectivity"
                        ]
                    },
                    ids: {
                        title: "Intrusion Detection",
                        steps: [
                            "Check IDS service is running",
                            "Verify signature database",
                            "Test alert generation",
                            "Check log aggregation",
                            "Validate false positive handling"
                        ]
                    }
                },
                monitoring: {
                    health: {
                        title: "Health Monitoring",
                        steps: [
                            "Check monitoring service status",
                            "Verify metric collection",
                            "Test alert thresholds",
                            "Check dashboard accessibility",
                            "Validate data retention"
                        ]
                    },
                    logging: {
                        title: "Log Aggregation",
                        steps: [
                            "Check logging service status",
                            "Verify log sources",
                            "Test log parsing and filtering",
                            "Check log retention policies",
                            "Validate log search functionality"
                        ]
                    },
                    tracing: {
                        title: "Distributed Tracing",
                        steps: [
                            "Check tracing service status",
                            "Verify trace collection",
                            "Test trace correlation",
                            "Check trace visualization",
                            "Validate performance impact"
                        ]
                    }
                },
                performance: {
                    qos: {
                        title: "Quality of Service",
                        steps: [
                            "Check QoS configuration",
                            "Test bandwidth limits",
                            "Verify traffic classification",
                            "Check queue statistics",
                            "Validate priority handling"
                        ]
                    },
                    loadBalancing: {
                        title: "Load Balancing",
                        steps: [
                            "Check load balancer configuration",
                            "Test traffic distribution",
                            "Verify health checks",
                            "Test failover scenarios",
                            "Check session persistence"
                        ]
                    },
                    acceleration: {
                        title: "XDP/eBPF Acceleration",
                        steps: [
                            "Check XDP program loading",
                            "Verify eBPF maps",
                            "Test packet processing",
                            "Check performance metrics",
                            "Validate bypass functionality"
                        ]
                    }
                }
            };

            // Feature selection
            document.addEventListener('click', function(e) {
                if (e.target.classList.contains('feature-item')) {
                    e.target.classList.toggle('selected');
                    const feature = e.target.dataset.feature;

                    if (e.target.classList.contains('selected')) {
                        selectedFeatures.push(feature);
                    } else {
                        selectedFeatures = selectedFeatures.filter(f => f !== feature);
                    }

                    updateChecklist();
                }
            });

            function updateChecklist() {
                const checklistContainer = document.getElementById('checklist');

                if (selectedFeatures.length === 0) {
                    checklistContainer.innerHTML = '<p>Select features above to load verification checklist...</p>';
                    return;
                }

                // Generate checklist based on selected features
                let checklistItems = [];
                let scenarioDetails = [];

                selectedFeatures.forEach(feature => {
                    if (verificationScenarios[feature]) {
                        Object.entries(verificationScenarios[feature]).forEach(([scenarioKey, scenario]) => {
                            checklistItems.push(...scenario.steps.map(step => `${scenario.title}: ${step}`));
                            scenarioDetails.push({
                                category: feature,
                                scenario: scenarioKey,
                                title: scenario.title,
                                steps: scenario.steps
                            });
                        });
                    }
                });

                checklistContainer.innerHTML = `
                    <div style="margin-bottom: 15px;">
                        <strong>Verification Scenarios:</strong> ${scenarioDetails.map(s => s.title).join(', ')}
                    </div>
                    ${checklistItems.map((item, index) => `
                        <div class="checklist-item" onclick="toggleChecklistItem(${index})">
                            <input type="checkbox" id="check-${index}" style="margin-right: 10px;">
                            <label for="check-${index}">${item}</label>
                        </div>
                    `).join('')}
                `;

                currentChecklist = checklistItems;
                currentScenarios = scenarioDetails;
            }

            function toggleChecklistItem(index) {
                const item = document.querySelector(`#check-${index}`).parentElement;
                item.classList.toggle('completed');
            }

            async function configureVM() {
                if (selectedFeatures.length === 0) {
                    alert('Please select at least one feature to test.');
                    return;
                }

                try {
                    await fetch('/api/vm/configure', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ features: selectedFeatures })
                    });
                    logVMAction(`Configured VM with features: ${selectedFeatures.join(', ')}`);
                    loadVMs();
                } catch (error) {
                    logVMAction(`Failed to configure VM: ${error.message}`);
                }
            }

            async function captureScreenshot() {
                try {
                    const response = await fetch('/api/evidence/screenshot', { method: 'POST' });
                    const result = await response.json();
                    addEvidenceItem('Screenshot', result.filename);
                    logVMAction('Screenshot captured');
                } catch (error) {
                    logVMAction(`Failed to capture screenshot: ${error.message}`);
                }
            }

            async function collectLogs() {
                try {
                    const response = await fetch('/api/evidence/logs', { method: 'POST' });
                    const result = await response.json();
                    addEvidenceItem('Logs', result.filename);
                    logVMAction('Logs collected');
                } catch (error) {
                    logVMAction(`Failed to collect logs: ${error.message}`);
                }
            }

            async function runTests() {
                try {
                    const response = await fetch('/api/tests/run', { method: 'POST' });
                    const result = await response.json();
                    addEvidenceItem('Test Results', result.filename);
                    logVMAction('Automated tests executed');
                } catch (error) {
                    logVMAction(`Failed to run tests: ${error.message}`);
                }
            }

            function addEvidenceItem(type, filename) {
                const container = document.getElementById('evidence-list');
                const item = document.createElement('div');
                item.innerHTML = `<p><strong>${type}:</strong> ${filename} <small>(${new Date().toLocaleString()})</small></p>`;
                container.appendChild(item);
            }

            async function submitSignoff() {
                const reviewer = document.getElementById('reviewer-name').value;
                const notes = document.getElementById('verification-notes').value;
                const status = document.getElementById('signoff-status');

                if (!reviewer.trim()) {
                    status.innerHTML = '<p style="color: red;">Please enter your name.</p>';
                    return;
                }

                try {
                    const response = await fetch('/api/signoff', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            reviewer: reviewer.trim(),
                            notes: notes.trim(),
                            timestamp: new Date().toISOString(),
                            features: selectedFeatures,
                            checklist: currentChecklist
                        })
                    });

                    if (response.ok) {
                        status.innerHTML = '<p style="color: green;">✅ Signoff submitted successfully!</p>';
                        logVMAction(`Human signoff submitted by ${reviewer}`);
                    } else {
                        throw new Error('Signoff submission failed');
                    }
                } catch (error) {
                    status.innerHTML = `<p style="color: red;">❌ Failed to submit signoff: ${error.message}</p>`;
                    logVMAction(`Signoff submission failed: ${error.message}`);
                }
            }

            async function loadSignoffs() {
                try {
                    const response = await fetch('/api/signoffs');
                    const signoffs = await response.json();
                    const signoffContainer = document.getElementById('signoff-list');

                    if (signoffs.length === 0) {
                        signoffContainer.innerHTML = '<p>No signoffs found.</p>';
                        return;
                    }

                    signoffContainer.innerHTML = signoffs.map(signoff => `
                        <div class="vm-card" style="margin-bottom: 15px;">
                            <h3>Signoff #${signoff.id}</h3>
                            <p><strong>Reviewer:</strong> ${signoff.reviewer}</p>
                            <p><strong>Features:</strong> ${signoff.features ? signoff.features.join(', ') : 'N/A'}</p>
                            <p><strong>Submitted:</strong> ${new Date(signoff.submitted_at).toLocaleString()}</p>
                            <p><strong>Status:</strong>
                                <span style="color: ${signoff.approved ? 'green' : 'orange'}">
                                    ${signoff.approved ? 'Approved' : 'Pending Approval'}
                                </span>
                            </p>
                            ${signoff.notes ? `<p><strong>Notes:</strong> ${signoff.notes}</p>` : ''}
                            ${!signoff.approved ? `
                                <div style="margin-top: 10px;">
                                    <input type="text" id="approver-${signoff.id}" placeholder="Your name" style="margin-right: 10px; padding: 5px;">
                                    <button class="btn btn-success" onclick="approveSignoff('${signoff.id}')">Approve</button>
                                </div>
                            ` : ''}
                            <div style="margin-top: 10px;">
                                <button class="btn btn-primary" onclick="downloadReport('${signoff.id}')">📄 Download Report</button>
                            </div>
                        </div>
                    `).join('');
                } catch (error) {
                    console.error('Failed to load signoffs:', error);
                    document.getElementById('signoff-list').innerHTML = '<p>Error loading signoffs.</p>';
                }
            }

            async function approveSignoff(signoffId) {
                const approverInput = document.getElementById(`approver-${signoffId}`);
                const approver = approverInput.value.trim();

                if (!approver) {
                    alert('Please enter your name for approval.');
                    return;
                }

                try {
                    const response = await fetch(`/api/signoff/${signoffId}/approve`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ approver, comments: '' })
                    });

                    if (response.ok) {
                        alert('Signoff approved successfully!');
                        loadSignoffs();
                    } else {
                        throw new Error('Approval failed');
                    }
                } catch (error) {
                    alert(`Failed to approve signoff: ${error.message}`);
                }
            }

            async function downloadReport(signoffId) {
                try {
                    const response = await fetch(`/api/reports/verification/${signoffId}`);
                    const report = await response.json();

                    // Create downloadable JSON file
                    const dataStr = JSON.stringify(report, null, 2);
                    const dataUri = 'data:application/json;charset=utf-8,'+ encodeURIComponent(dataStr);

                    const exportFileDefaultName = `verification-report-${signoffId}.json`;

                    const linkElement = document.createElement('a');
                    linkElement.setAttribute('href', dataUri);
                    linkElement.setAttribute('download', exportFileDefaultName);
                    linkElement.click();

                    logVMAction(`Report downloaded: ${exportFileDefaultName}`);
                } catch (error) {
                    alert(`Failed to download report: ${error.message}`);
                }
            }

            // Initialize
            loadVMs();
            setInterval(loadVMs, 5000); // Refresh VM status every 5 seconds
        </script>
    </body>
    </html>
    EOF

    # Create API server
    cat > $out/share/simulator-web/server.js << 'EOF'
    const express = require('express');
    const fs = require('fs');
    const path = require('path');
    const { exec } = require('child_process');

    const app = express();
    app.use(express.json());

    const STATE_DIR = '/var/lib/simulator';

    // Ensure directories exist
    function ensureDirectories() {
        const dirs = [
            path.join(STATE_DIR, 'logs'),
            path.join(STATE_DIR, 'evidence'),
            path.join(STATE_DIR, 'vms')
        ];
        dirs.forEach(dir => {
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
        });
    }

    ensureDirectories();

    // API endpoints
    app.get('/api/vms', (req, res) => {
        try {
            const vmDir = path.join(STATE_DIR, 'vms');
            const vms = [];

            if (fs.existsSync(vmDir)) {
                const vmNames = fs.readdirSync(vmDir);
                vmNames.forEach(name => {
                    const vmPath = path.join(vmDir, name);
                    const pidFile = path.join(vmPath, 'pid');

                    let status = 'stopped';
                    let ip = null;
                    let features = [];

                    if (fs.existsSync(pidFile)) {
                        try {
                            const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim());
                            // Check if process is running
                            process.kill(pid, 0);
                            status = 'running';
                        } catch (e) {
                            status = 'stopped';
                        }
                    }

                    // Try to read configuration
                    const configFile = path.join(vmPath, 'gateway-config.nix');
                    if (fs.existsSync(configFile)) {
                        try {
                            const config = fs.readFileSync(configFile, 'utf8');
                            // Simple feature extraction (would need proper Nix parsing)
                            if (config.includes('routing')) features.push('routing');
                            if (config.includes('firewall')) features.push('firewall');
                            if (config.includes('monitoring')) features.push('monitoring');
                        } catch (e) {
                            // Ignore config read errors
                        }
                    }

                    vms.push({
                        name,
                        status,
                        ip: ip || '192.168.1.1', // Default IP
                        features
                    });
                });
            }

            res.json(vms);
        } catch (error) {
            console.error('Error reading VMs:', error);
            res.status(500).json({ error: 'Failed to read VM status' });
        }
    });

    app.post('/api/vms/:name/start', (req, res) => {
        const vmName = req.params.name;

        // Send command to orchestrator via file signal
        const signalFile = path.join(STATE_DIR, 'commands', `start-${vmName}`);
        ensureDirectories();
        fs.writeFileSync(signalFile, JSON.stringify({ command: 'start', vm: vmName }));

        res.json({ status: 'command_sent', vm: vmName });
    });

    app.post('/api/vms/:name/stop', (req, res) => {
        const vmName = req.params.name;

        const signalFile = path.join(STATE_DIR, 'commands', `stop-${vmName}`);
        ensureDirectories();
        fs.writeFileSync(signalFile, JSON.stringify({ command: 'stop', vm: vmName }));

        res.json({ status: 'command_sent', vm: vmName });
    });

    app.post('/api/vms/:name/reset', (req, res) => {
        const vmName = req.params.name;

        const signalFile = path.join(STATE_DIR, 'commands', `reset-${vmName}`);
        ensureDirectories();
        fs.writeFileSync(signalFile, JSON.stringify({ command: 'reset', vm: vmName }));

        res.json({ status: 'command_sent', vm: vmName });
    });

    app.post('/api/vm/configure', (req, res) => {
        const { features } = req.body;

        const configFile = path.join(STATE_DIR, 'configs', 'gateway.nix');
        ensureDirectories();

        // Generate Nix configuration based on features
        let config = '{ config, lib, ... }:\n{\n  services.gateway = {\n    enable = true;\n    interfaces = {\n      lan = "eth0";\n      wan = "eth1";\n    };\n';

        if (features && features.length > 0) {
            config += '    features = [ ';
            config += features.map(f => `"${f}"`).join(' ');
            config += ' ];\n';
        }

        config += '  };\n}\n';

        fs.writeFileSync(configFile, config);

        // Audit log
        logAudit('vm_configured', 'web-user', { features });

        res.json({ status: 'configured', features });
    });

    app.post('/api/evidence/screenshot', (req, res) => {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const filename = `screenshot-${timestamp}.png`;

        // In a real implementation, this would capture a screenshot
        // For now, just create a placeholder
        const evidenceFile = path.join(STATE_DIR, 'evidence', filename);
        fs.writeFileSync(evidenceFile, 'Screenshot placeholder - ' + new Date().toISOString());

        // Audit log
        logAudit('evidence_collected', 'web-user', { type: 'screenshot', filename });

        res.json({ filename, path: evidenceFile });
    });

    app.post('/api/evidence/logs', (req, res) => {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const filename = `logs-${timestamp}.log`;

        const evidenceFile = path.join(STATE_DIR, 'evidence', filename);

        // Collect logs from various sources
        let logContent = `Log collection - ${new Date().toISOString()}\n\n`;

        const logFiles = [
            path.join(STATE_DIR, 'logs', 'simulator.log'),
            '/var/log/simulator.log'
        ];

        logFiles.forEach(logFile => {
            if (fs.existsSync(logFile)) {
                try {
                    logContent += `=== ${logFile} ===\n`;
                    logContent += fs.readFileSync(logFile, 'utf8') + '\n\n';
                } catch (e) {
                    logContent += `Error reading ${logFile}: ${e.message}\n\n`;
                }
            }
        });

        fs.writeFileSync(evidenceFile, logContent);

        // Audit log
        logAudit('evidence_collected', 'web-user', { type: 'logs', filename });

        res.json({ filename, path: evidenceFile });
    });

    app.post('/api/tests/run', (req, res) => {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const filename = `test-results-${timestamp}.json`;

        const evidenceFile = path.join(STATE_DIR, 'evidence', filename);

        // Run basic connectivity tests
        exec('ping -c 3 192.168.1.1', (error, stdout, stderr) => {
            const results = {
                timestamp: new Date().toISOString(),
                tests: [{
                    name: 'Gateway Connectivity',
                    status: error ? 'failed' : 'passed',
                    output: stdout || stderr
                }]
            };

            fs.writeFileSync(evidenceFile, JSON.stringify(results, null, 2));

            // Audit log
            logAudit('tests_executed', 'web-user', { filename, test_count: results.tests.length });

            res.json({ filename, path: evidenceFile, results });
        });
    });

    // Audit logging function
    function logAudit(action, user, details = {}) {
        const auditEntry = {
            timestamp: new Date().toISOString(),
            action,
            user,
            details,
            ip: 'web-interface', // In real impl, get from request
            session_id: Date.now().toString()
        };

        const auditFile = path.join(STATE_DIR, 'logs', 'audit.log');
        fs.appendFileSync(auditFile, JSON.stringify(auditEntry) + '\n');
        console.log(`AUDIT: ${action} by ${user}`);
    }

    app.post('/api/signoff', (req, res) => {
        const signoff = req.body;
        const logFile = path.join(STATE_DIR, 'logs', 'signoffs.log');

        const signoffEntry = {
            ...signoff,
            id: Date.now().toString(),
            submitted_at: new Date().toISOString()
        };

        fs.appendFileSync(logFile, JSON.stringify(signoffEntry) + '\n');

        // Also save to evidence
        const evidenceFile = path.join(STATE_DIR, 'evidence', `signoff-${signoffEntry.id}.json`);
        fs.writeFileSync(evidenceFile, JSON.stringify(signoffEntry, null, 2));

        // Audit log
        logAudit('signoff_submitted', signoff.reviewer, {
            signoff_id: signoffEntry.id,
            features: signoff.features
        });

        res.json({ status: 'recorded', id: signoffEntry.id });
    });

    app.get('/api/signoffs', (req, res) => {
        try {
            const signoffs = [];
            const signoffFiles = fs.readdirSync(path.join(STATE_DIR, 'evidence'))
                .filter(file => file.startsWith('signoff-'))
                .map(file => path.join(STATE_DIR, 'evidence', file));

            signoffFiles.forEach(file => {
                try {
                    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
                    signoffs.push(data);
                } catch (e) {
                    console.error(`Error reading signoff file ${file}:`, e);
                }
            });

            res.json(signoffs);
        } catch (error) {
            console.error('Error listing signoffs:', error);
            res.status(500).json({ error: 'Failed to list signoffs' });
        }
    });

    app.post('/api/signoff/:id/approve', (req, res) => {
        const signoffId = req.params.id;
        const { approver, comments } = req.body;

        // In a real implementation, this would call the signoff DB service
        console.log(`Approval requested for signoff ${signoffId} by ${approver}`);

        // For now, just update the evidence file
        const evidenceFile = path.join(STATE_DIR, 'evidence', `signoff-${signoffId}.json`);
        if (fs.existsSync(evidenceFile)) {
            const signoff = JSON.parse(fs.readFileSync(evidenceFile, 'utf8'));
            signoff.approvals = signoff.approvals || [];
            signoff.approvals.push({
                approver_name: approver,
                approved_at: new Date().toISOString(),
                comments: comments || ''
            });

            // Check approval threshold (simplified)
            if (signoff.approvals.length >= 1) { // In real impl, use configured threshold
                signoff.approved = true;
                signoff.approved_at = new Date().toISOString();
            }

            fs.writeFileSync(evidenceFile, JSON.stringify(signoff, null, 2));

            // Audit log
            logAudit('signoff_approved', approver, { signoff_id: signoffId });

            res.json({ status: 'approved', signoff });
        } else {
            res.status(404).json({ error: 'Signoff not found' });
        }
    });

    app.get('/api/reports/verification/:signoffId', (req, res) => {
        const signoffId = req.params.signoffId;

        try {
            const evidenceFile = path.join(STATE_DIR, 'evidence', `signoff-${signoffId}.json`);
            if (!fs.existsSync(evidenceFile)) {
                return res.status(404).json({ error: 'Signoff not found' });
            }

            const signoff = JSON.parse(fs.readFileSync(evidenceFile, 'utf8'));

            // Generate comprehensive report
            const report = {
                report_id: `report-${signoffId}`,
                generated_at: new Date().toISOString(),
                signoff: signoff,
                evidence_files: [],
                test_results: [],
                summary: {
                    features_tested: signoff.features || [],
                    approval_status: signoff.approved ? 'approved' : 'pending',
                    reviewer: signoff.reviewer,
                    submitted_at: signoff.submitted_at
                }
            };

            // Collect evidence files
            const evidenceDir = path.join(STATE_DIR, 'evidence');
            if (fs.existsSync(evidenceDir)) {
                const files = fs.readdirSync(evidenceDir);
                report.evidence_files = files
                    .filter(file => file.includes(signoffId) || file.includes('test-results'))
                    .map(file => ({
                        filename: file,
                        path: path.join(evidenceDir, file),
                        size: fs.statSync(path.join(evidenceDir, file)).size
                    }));
            }

            // Collect test results
            const testResultsDir = path.join(STATE_DIR, 'test-results');
            if (fs.existsSync(testResultsDir)) {
                const testFiles = fs.readdirSync(testResultsDir);
                testFiles.forEach(file => {
                    try {
                        const testData = JSON.parse(fs.readFileSync(path.join(testResultsDir, file), 'utf8'));
                        report.test_results.push(testData);
                    } catch (e) {
                        console.error(`Error reading test file ${file}:`, e);
                    }
                });
            }

            res.json(report);
        } catch (error) {
            console.error('Error generating report:', error);
            res.status(500).json({ error: 'Failed to generate report' });
        }
    });

    app.get('/api/reports/download/:signoffId', (req, res) => {
        const signoffId = req.params.signoffId;

        // Generate and download comprehensive report as JSON
        const reportUrl = `/api/reports/verification/${signoffId}`;
        res.redirect(reportUrl);
    });

    app.listen(3000, () => {
        console.log('Simulator API server running on port 3000');
    });
    EOF

    # Create package.json for Node.js dependencies
    cat > $out/share/simulator-web/package.json << 'EOF'
    {
      "name": "simulator-web",
      "version": "1.0.0",
      "dependencies": {
        "express": "^4.18.0"
      }
    }
    EOF
  '';
}
# NixOS Gateway Configuration Framework - Local TUI/GTK4/Web UI User Stories

## Overview

This document details user stories and interface specifications for a **local-only** TUI/GTK4/Web UI that runs directly on the NixOS gateway system. This is not a remote management interface, but rather a local administration tool for gateway configuration and monitoring.

## 🎯 **Primary User Personas**

### 1. System Administrator (Local Admin)
- **Experience**: 3-10 years in Linux system administration
- **Environment**: Physical access to gateway hardware
- **Goals**: Configure and monitor gateway locally without SSH
- **Pain Points**: Complex NixOS configuration files, manual editing errors
- **Frequency**: Daily local administration tasks

### 2. Network Engineer (Field Engineer)
- **Experience**: 2-8 years in network engineering
- **Environment**: On-site gateway installation and maintenance
- **Goals**: Quick configuration during deployment and troubleshooting
- **Pain Points**: Need to configure systems in console environments
- **Frequency**: During deployments and maintenance windows

### 3. Security Officer (Local Security Admin)
- **Experience**: 4-12 years in network security
- **Environment**: Local security management and compliance
- **Goals**: Manage local security policies and monitor threats
- **Pain Points**: Complex security configuration syntax
- **Frequency**: Daily security monitoring and policy updates

## 🖥️ **TUI (Terminal User Interface) Requirements**

### Main TUI Layout
```
┌─────────────────────────────────────────────────────────────────┐
│ NixOS Gateway Configuration v2.1.0                    │
│ [F1]Help [F2]Save [F3]Apply [F4]Exit [F5]Refresh     │
├─────────────────────────────────────────────────────────────────┤
│ ┌─Menu─┐ ┌─Configuration─┐ ┌─Status─┐ ┌─Logs─┐ │
│ │Network │ │ networking.interfaces │ │ System  │ │ Recent │ │
│ │Firewall│ │ services.gateway   │ │ Network │ │ Errors │ │
│ │Security│ │                   │ │ Security│ │        │ │
│ │Monitor │ │                   │ │ Services│ │        │ │
│ │System  │ │                   │ │ Hardware│ │        │ │
│ │Help    │ │                   │ │         │ │        │ │
│ └───────┘ └───────────────────┘ └─────────┘ └───────┘ │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Configuration Editor: networking.interfaces              │ │
│ │                                                         │ │
│ │ {                                                      │ │
│ │   wan = "enp1s0";                                     │ │
│ │   lan = "enp2s0";                                     │ │
│ │   mgmt = "enp3s0";                                    │ │
│ │ }                                                      │ │
│ │                                                         │ │
│ │ [↑] Previous [↓] Next [F6]Validate [F7]Save [F8]Apply │ │
│ └─────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│ Status: Configuration valid | Last saved: 2024-12-14 15:30 │
│ System: Online | Uptime: 15d 3h 22m | Load: 0.45    │
└─────────────────────────────────────────────────────────────────┘
```

### TUI Navigation Elements
- **Menu Navigation**: Left sidebar with category selection (↑↓ arrows)
- **Configuration Editor**: Main content area with syntax highlighting
- **Status Bar**: Bottom status bar with system information
- **Function Keys**: F1-F8 for common actions
- **Keyboard Shortcuts**: Full keyboard navigation support

### TUI Interactive Elements
- **Menu Items**: Text-based menu with keyboard navigation
- **Configuration Editor**: Text editor with syntax highlighting and validation
- **Status Indicators**: Color-coded status information
- **Progress Bars**: Visual progress for long operations
- **Dialog Boxes**: Modal dialogs for confirmations and inputs
- **Help System**: Context-sensitive help with F1 key

## 🖼️ **GTK4 Desktop Interface Requirements**

### Main GTK4 Window Layout
```
┌─────────────────────────────────────────────────────────────────┐
│ NixOS Gateway Configuration                    [_][□][×] │
├─────────────────────────────────────────────────────────────────┤
│ File Edit View Tools Help                               │
├─────────────────────────────────────────────────────────────────┤
│ ┌─Modules─┐ ┌─Configuration─┐ ┌─Status─┐ ┌─Logs─┐ │
│ │🌐 Network│ │ networking.interfaces │ │ 📊 System│ │ 📜 Recent│ │
│ │🛡️ Firewall│ │ services.gateway   │ │ 🌍 Network│ │ ⚠️ Errors│ │
│ │🔐 Security│ │                   │ │ 🛡️ Security│ │        │ │
│ │📊 Monitor │ │                   │ │ ⚙️ Services│ │        │ │
│ │⚙️ System  │ │                   │ │ 💾 Hardware│ │        │ │
│ │❓ Help    │ │                   │ │         │ │        │ │
│ └─────────┘ └───────────────────┘ └─────────┘ └───────┘ │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Configuration Editor: networking.interfaces              │ │
│ │ ┌─Visual─┐ ┌─Code─┐ ┌─Preview─┐              │ │
│ │ │         │ │         │ │         │              │ │
│ │ │ [📦]   │ │ {       │ │ wan:    │              │ │
│ │ │ Network │ │   wan = │ │ enp1s0 │              │ │
│ │ │ Config  │ │   "enp1s0"; │ │ lan:    │              │ │
│ │ │ Builder │ │   lan = │ │ enp2s0 │              │ │
│ │ │         │ │   "enp2s0"; │ │ mgmt:   │              │ │
│ │ │         │ │   mgmt = │ │ enp3s0 │              │ │
│ │ │         │ │   "enp3s0"; │ │         │              │ │
│ │ │         │ │ }       │ │         │              │ │
│ │ │         │ │         │ │         │              │ │
│ │ └─────────┘ └─────────┘ └─────────┘              │ │
│ │                                                         │ │
│ │ [💾 Save] [🔄 Apply] [🔍 Validate] [📋 Templates]   │ │
│ └─────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│ Status: ✅ Configuration valid | Last applied: 2h ago     │
│ System: 🟢 Online | Uptime: 15d 3h | Load: 0.45     │
└─────────────────────────────────────────────────────────────────┘
```

### GTK4 Interface Elements
- **Module Sidebar**: Icon-based module selection with tooltips
- **Configuration Tabs**: Visual builder, code editor, preview tabs
- **Visual Builder**: Drag-and-drop interface for configuration
- **Code Editor**: Syntax-highlighted text editor with validation
- **Preview Panel**: Live preview of configuration changes
- **Status Bar**: Real-time system status and configuration state
- **Menu Bar**: File, Edit, View, Tools, Help menus

### GTK4 Interactive Elements
- **Buttons**: Primary, secondary, and icon buttons
- **Text Inputs**: Configuration fields with validation
- **Dropdowns**: Selection menus for options
- **Checkboxes**: Boolean option selection
- **Tabs**: Navigation between related content
- **Trees**: Hierarchical configuration display
- **Lists**: Configuration items and logs
- **Dialogs**: Modal dialogs for confirmations and inputs
- **Tooltips**: Context-sensitive help on hover

## 🌐 **Local Web Interface Requirements**

### Web Interface Layout
```
┌─────────────────────────────────────────────────────────────────┐
│ NixOS Gateway Configuration                    [🔧][❓][×] │
├─────────────────────────────────────────────────────────────────┤
│ http://localhost:8080 | Connected | Local Mode Only     │
├─────────────────────────────────────────────────────────────────┤
│ ┌─Modules─┐ ┌─Configuration─┐ ┌─Status─┐ ┌─Logs─┐ │
│ │🌐 Network│ │ networking.interfaces │ │ 📊 System│ │ 📜 Recent│ │
│ │🛡️ Firewall│ │ services.gateway   │ │ 🌍 Network│ │ ⚠️ Errors│ │
│ │🔐 Security│ │                   │ │ 🛡️ Security│ │        │ │
│ │📊 Monitor │ │                   │ │ ⚙️ Services│ │        │ │
│ │⚙️ System  │ │                   │ │ 💾 Hardware│ │        │ │
│ │❓ Help    │ │                   │ │         │ │        │ │
│ └─────────┘ └───────────────────┘ └─────────┘ └───────┘ │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Configuration Editor: networking.interfaces              │ │
│ │ ┌─Visual─┐ ┌─Code─┐ ┌─Preview─┐              │ │
│ │ │         │ │         │ │         │              │ │
│ │ │ [📦]   │ │ {       │ │ wan:    │              │ │
│ │ │ Network │ │   wan = │ │ enp1s0 │              │ │
│ │ │ Config  │ │   "enp1s0"; │ │ lan:    │              │ │
│ │ │ Builder │ │   lan = │ │ enp2s0 │              │ │
│ │ │         │ │   "enp2s0"; │ │ mgmt:   │              │ │
│ │ │         │ │   mgmt = │ │ enp3s0 │              │ │
│ │ │         │ │   "enp3s0"; │ │         │              │ │
│ │ │         │ │ }       │ │         │              │ │
│ │ │         │ │         │ │         │              │ │
│ │ └─────────┘ └─────────┘ └─────────┘              │ │
│ │                                                         │ │
│ │ [💾 Save] [🔄 Apply] [🔍 Validate] [📋 Templates]   │ │
│ └─────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│ Status: ✅ Configuration valid | Last applied: 2h ago     │
│ System: 🟢 Online | Uptime: 15d 3h | Load: 0.45     │
└─────────────────────────────────────────────────────────────────┘
```

### Web Interface Elements
- **Module Navigation**: Icon-based navigation with descriptions
- **Configuration Workspace**: Multi-tab interface for different views
- **Visual Builder**: Drag-and-drop configuration interface
- **Code Editor**: Monaco/CodeMirror editor with NixOS syntax highlighting
- **Live Preview**: Real-time configuration preview
- **Status Dashboard**: System status and metrics display
- **Local Mode Indicator**: Clear indication of local-only operation

## 🎯 **Local-Specific User Stories**

### Story 1: Console Configuration (TUI)
**As** System Administrator (Local Admin)  
**I want** to configure the gateway using a terminal interface  
**So that** I can work efficiently in console environments without GUI dependencies

**Acceptance Criteria:**
- Full keyboard navigation with intuitive shortcuts
- Syntax highlighting for NixOS configuration
- Real-time validation with clear error messages
- Configuration templates for common setups
- System status display without external tools
- Works over SSH connections
- F1-F8 function key support for common actions

### Story 2: Visual Configuration (GTK4)
**As** Network Engineer (Field Engineer)  
**I want** to use a visual interface on the gateway console  
**So that** I can quickly configure systems during deployment

**Acceptance Criteria:**
- Native GTK4 application that runs locally
- Visual configuration builder with drag-and-drop
- Code editor with syntax highlighting and validation
- Live preview of configuration changes
- Template library for common configurations
- System integration with desktop environment
- Works without network connectivity

### Story 3: Web-Based Local Management
**As** Security Officer (Local Security Admin)  
**I want** to manage the gateway through a local web interface  
**So that** I can use familiar web-based tools while maintaining local control

**Acceptance Criteria:**
- Local web server on port 8080 (localhost only)
- Modern web interface with responsive design
- Real-time configuration validation and preview
- Integration with local system services
- Works without internet connectivity
- Browser-based access from any local machine

### Story 4: Quick Status Monitoring
**As** System Administrator (Local Admin)  
**I want** to quickly view system status and health  
**So that** I can identify issues without external monitoring tools

**Acceptance Criteria:**
- At-a-glance system status display
- Real-time metrics (CPU, memory, network)
- Service status indicators
- Recent log entries with filtering
- Hardware health monitoring
- Alert notifications for critical issues

### Story 5: Configuration Templates
**As** Network Engineer (Field Engineer)  
**I want** to use pre-built configuration templates  
**So that** I can quickly deploy standard gateway configurations

**Acceptance Criteria:**
- Template library for common deployment scenarios
- Template customization and parameterization
- One-click template application
- Template validation and testing
- Custom template creation and saving
- Template import/export functionality

### Story 6: Configuration Validation
**As** System Administrator (Local Admin)  
**I want** to validate configurations before applying them  
**So that** I can prevent configuration errors and system downtime

**Acceptance Criteria:**
- Real-time syntax validation
- Configuration best practices checking
- Error highlighting with explanations
- Configuration diff and comparison
- Test deployment in sandbox environment
- Rollback capability for failed changes

### Story 7: Local Backup Management
**As** Security Officer (Local Security Admin)  
**I want** to manage local configuration backups  
**So that** I can recover from configuration errors quickly

**Acceptance Criteria:**
- Automatic backup creation before changes
- Manual backup creation and management
- Backup restoration with validation
- Backup scheduling and retention
- Backup encryption and security
- Backup verification and integrity checking

## 🔧 **Technical Implementation Considerations**

### TUI Implementation
- **Framework**: ncurses-based or similar terminal UI library
- **Language**: C or Rust for performance
- **Dependencies**: Minimal system dependencies
- **Configuration**: File-based configuration in /etc/nixos-gateway/
- **Integration**: Direct integration with NixOS configuration system
- **Permissions**: Root/sudo access for configuration changes

### GTK4 Implementation
- **Framework**: GTK4 with Rust or C bindings
- **Language**: Rust for memory safety and performance
- **Dependencies**: GTK4, glib, system libraries
- **Configuration**: Same backend as TUI and web interfaces
- **Desktop Integration**: Desktop file associations and shortcuts
- **Theme Support**: System theme integration

### Web Implementation
- **Framework**: Local web server (no external dependencies)
- **Frontend**: Modern JavaScript framework (React/Vue.js)
- **Backend**: Lightweight HTTP server with REST API
- **Communication**: Local-only, localhost binding only
- **Security**: No external network access, local authentication
- **Storage**: File-based configuration storage

## 🎨 **Local-Only Features**

### Security Considerations
- **Local Binding**: All services bind to localhost only
- **No Remote Access**: Explicitly disable remote management
- **File Permissions**: Proper file permissions for configuration files
- **Process Isolation**: Run with appropriate user permissions
- **Audit Logging**: Local audit trail for all changes

### Performance Considerations
- **Minimal Overhead**: Lightweight interfaces for gateway performance
- **Fast Startup**: Quick application startup times
- **Responsive UI**: Immediate feedback for all actions
- **Resource Usage**: Low CPU and memory usage
- **Background Operations**: Non-blocking background tasks

### Integration Requirements
- **NixOS Integration**: Direct integration with NixOS configuration
- **System Services**: Integration with systemd services
- **File System**: Proper file handling and permissions
- **Process Management**: Safe process handling and signaling
- **Hardware Access**: Appropriate hardware interface access

## 📋 **Interface Comparison**

| Feature | TUI | GTK4 | Web |
|----------|------|--------|-----|
| **Resource Usage** | Very Low | Low | Medium |
| **Remote Access** | SSH Only | Local Only | Local Only |
| **Visual Builder** | No | Yes | Yes |
| **Code Editor** | Basic | Advanced | Advanced |
| **System Integration** | Terminal | Desktop | Browser |
| **Learning Curve** | Medium | Low | Low |
| **Performance** | Excellent | Good | Good |
| **Accessibility** | Screen Reader | Full | Full |
| **Customization** | Themes | Themes | Full |

## 🚀 **Implementation Priority**

### Phase 1: Core TUI
1. Basic TUI framework with menu navigation
2. Configuration editor with syntax highlighting
3. System status display
4. Configuration validation
5. Basic template support

### Phase 2: GTK4 Interface
1. GTK4 application framework
2. Visual configuration builder
3. Advanced code editor
4. System integration
5. Template management

### Phase 3: Local Web Interface
1. Local web server setup
2. Modern web frontend
3. REST API backend
4. Real-time validation
5. Advanced features

This specification provides detailed requirements for local-only TUI/GTK4/Web interfaces that run directly on the NixOS gateway system, with no remote access capabilities and full integration with the local system.
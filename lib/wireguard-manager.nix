{ lib }:

{
  # Convert the attribute set of peers to the list format expected by networking.wireguard
  peersToList =
    peersAttrs:
    lib.mapAttrsToList (name: peerConfig: {
      publicKey = peerConfig.publicKey;
      allowedIPs = peerConfig.allowedIPs;
      endpoint = peerConfig.endpoint; # Optional, might be null
      persistentKeepalive = peerConfig.persistentKeepalive;
      # Store extra metadata if needed, though networking.wireguard won't use it directly
    }) peersAttrs;

  # Convert peers to systemd-networkd .netdev WireGuardPeer section format
  peersToNetdev =
    peersAttrs:
    lib.mapAttrsToList (
      name: peerConfig:
      {
        PublicKey = peerConfig.publicKey;
        AllowedIPs = peerConfig.allowedIPs;
        PersistentKeepalive =
          if peerConfig.persistentKeepalive != null then peerConfig.persistentKeepalive else 0;
      }
      // (if peerConfig.endpoint != null then { Endpoint = peerConfig.endpoint; } else { })
    ) peersAttrs;

  # Generate NAT rules for peers that need it
  # logic: If a peer has specific subnets they are advertising/routing, we might need NAT
  # For the server itself, we usually want to masquerade traffic leaving the VPN interface if it's going to the WAN
  generatePostSetup =
    {
      interface,
      wanInterface,
      peers,
      ipv4Cidr,
      ipv6Cidr,
      iptablesBin ? "iptables",
      ip6tablesBin ? "ip6tables",
    }:
    let
      # Basic masquerade for VPN traffic going out to WAN
      masqueradeRule = ''
        ${iptablesBin} -t nat -A POSTROUTING -s ${ipv4Cidr} -o ${wanInterface} -j MASQUERADE
        ${ip6tablesBin} -t nat -A POSTROUTING -s ${ipv6Cidr} -o ${wanInterface} -j MASQUERADE
      '';
    in
    ''
      ${masqueradeRule}
    '';

  generatePostShutdown =
    {
      interface,
      wanInterface,
      ipv4Cidr,
      ipv6Cidr,
      iptablesBin ? "iptables",
      ip6tablesBin ? "ip6tables",
    }:
    ''
      ${iptablesBin} -t nat -D POSTROUTING -s ${ipv4Cidr} -o ${wanInterface} -j MASQUERADE 2>/dev/null || true
      ${ip6tablesBin} -t nat -D POSTROUTING -s ${ipv6Cidr} -o ${wanInterface} -j MASQUERADE 2>/dev/null || true
    '';

  # Generate key rotation script
  mkKeyRotationScript =
    {
      interface,
      interval,
      notifyBefore,
    }:
    ''
      # Key Rotation Logic
      KEY_FILE="/var/lib/wireguard/${interface}.key"
      PUB_FILE="/var/lib/wireguard/${interface}.pub"

      if [ ! -f "$KEY_FILE" ]; then
        echo "Key file missing, skipping rotation check."
        exit 0
      fi

      # Check key age
      KEY_AGE=$(($(date +%s) - $(stat -c %Y "$KEY_FILE")))
      # Simple days to seconds conversion (assuming interval is just a number of days for now)
      # In a real impl, we'd parse "90d" properly
      INTERVAL_SEC=$((${interval} * 86400))

      if [ "$KEY_AGE" -gt "$INTERVAL_SEC" ]; then
        echo "Rotating WireGuard keys for ${interface}..."
        # Backup old keys
        mv "$KEY_FILE" "$KEY_FILE.bak"
        mv "$PUB_FILE" "$PUB_FILE.bak"
        
        # Generate new keys
        wg genkey > "$KEY_FILE"
        wg pubkey < "$KEY_FILE" > "$PUB_FILE"
        chmod 600 "$KEY_FILE"
        
        # Restart interface (simplified, in production might want smoother rollover)
        systemctl restart wireguard-${interface}
        
        echo "Keys rotated. New public key: $(cat "$PUB_FILE")"
      else
        echo "Keys are fresh enough."
      fi
    '';

  # Generate monitoring script
  mkMonitoringScript =
    { interface, peers }:
    ''
      echo "WireGuard Monitoring for ${interface}"
      echo "------------------------------------"
      wg show ${interface} dump | tail -n +2 | while read -r peer psk endpoint allowed_ips handshake transfer_rx transfer_tx persistent_keepalive; do
        # Find peer name from config if possible (requires mapping, skipping for now)
        NOW=$(date +%s)
        LAST_HANDSHAKE=$((NOW - handshake))
        
        STATUS="HEALTHY"
        if [ "$handshake" -eq 0 ]; then
             STATUS="INACTIVE"
        elif [ "$LAST_HANDSHAKE" -gt 180 ]; then
             STATUS="STALE"
        fi
        
        echo "Peer: $peer"
        echo "  Endpoint: $endpoint"
        echo "  Status: $STATUS"
        echo "  Last Handshake: $((LAST_HANDSHAKE))s ago"
        echo "  Transfer: RX=$(numfmt --to=iec $transfer_rx) TX=$(numfmt --to=iec $transfer_tx)"
        echo ""
      done
    '';
}

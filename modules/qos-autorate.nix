# gw/qos-autorate.nix
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.qos;
  wwanIface = config.services.gateway.interfaces.wwan;

  # Script to dynamically adjust CAKE bandwidth based on latency
  autorateScript = pkgs.writeShellScript "qos-autorate" ''
    set -u

    IFACE="${wwanIface}"
    TARGET="1.1.1.1"

    # Config
    MIN_BW=5000    # 5 Mbit Floor
    MAX_BW=100000  # 100 Mbit Ceiling
    CUR_BW=20000   # Start at 20 Mbit

    # Thresholds (ms)
    BASE_RTT=0
    TARGET_RTT=100 # If RTT > 100ms, we are congested

    update_shaper() {
      ${pkgs.iproute2}/bin/tc qdisc change dev $IFACE root cake bandwidth ''${1}kbit diffserv4 nat dual-dsthost ack-filter
      # We also need to update ingress (IFB) similarly
      if [ -d "/sys/class/net/ifb-$IFACE" ]; then
         ${pkgs.iproute2}/bin/tc qdisc change dev ifb-$IFACE root cake bandwidth ''${1}kbit diffserv4 nat dual-srchost ingress
      fi
    }

    echo "Starting Auto-Rate QoS on $IFACE..."

    # 1. Determine Baseline RTT (idle latency)
    BASE_RTT=$(${pkgs.iputils}/bin/ping -c 5 -i 0.2 -W 1 $TARGET | tail -1 | awk -F '/' '{print int($2)}')
    echo "Baseline RTT: ''${BASE_RTT}ms"

    while true; do
      # Get current RTT (short sample)
      curr_rtt=$(${pkgs.iputils}/bin/ping -c 4 -i 0.2 -W 1 $TARGET | tail -1 | awk -F '/' '{print int($2)}')
      
      # Congestion Logic
      if [ "$curr_rtt" -gt "$((BASE_RTT + 50))" ]; then
         # Latency Spike! Congestion detected. Drop BW by 10%
         NEW_BW=$(echo "$CUR_BW * 0.9" | ${pkgs.bc}/bin/bc | cut -d. -f1)
         if [ "$NEW_BW" -lt "$MIN_BW" ]; then NEW_BW=$MIN_BW; fi
         echo "Congestion (RTT $curr_rtt). Dropping BW: $CUR_BW -> $NEW_BW"
         CUR_BW=$NEW_BW
         update_shaper $CUR_BW
         
      elif [ "$curr_rtt" -lt "$((BASE_RTT + 20))" ]; then
         # Latency is good. Probe up by 5% to reclaim bandwidth
         if [ "$CUR_BW" -lt "$MAX_BW" ]; then
            NEW_BW=$(echo "$CUR_BW * 1.05" | ${pkgs.bc}/bin/bc | cut -d. -f1)
            echo "Link Clear (RTT $curr_rtt). Raising BW: $CUR_BW -> $NEW_BW"
            CUR_BW=$NEW_BW
            update_shaper $CUR_BW
         fi
      fi
      
      sleep 5
    done
  '';
in
{
  systemd.services.qos-autorate = lib.mkIf cfg.adaptiveWwan {
    description = "Adaptive QoS Controller";
    after = [ "qos-setup.service" ];
    requires = [ "qos-setup.service" ];
    serviceConfig = {
      ExecStart = autorateScript;
      Restart = "always";
      Type = "simple";
    };
  };
}

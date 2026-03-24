{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway-dev-tools;
in
{
  options.services.gateway-dev-tools = {
    enable = lib.mkEnableOption "NixOS Gateway Development Tools (Home Manager)";

    installTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install monitoring tools (grafana, loki, promtail, etc.) to user profile";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.mkIf cfg.installTools (
      with pkgs;
      [
        grafana
        grafana-loki
        promtail
        jq
        nmap
      ]
    );

    # Helper aliases for interacting with the local monitoring stack
    programs.bash.shellAliases = {
      mon-check-loki = "curl -s http://localhost:3100/ready";
      mon-check-grafana = "curl -s http://localhost:3000/api/health";
      mon-query-logs = "logcli query --addr=http://localhost:3100 --output=json";
    };

    programs.zsh.shellAliases = {
      mon-check-loki = "curl -s http://localhost:3100/ready";
      mon-check-grafana = "curl -s http://localhost:3000/api/health";
      mon-query-logs = "logcli query --addr=http://localhost:3100 --output=json";
    };
  };
}

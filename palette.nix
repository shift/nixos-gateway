# palette.nix
# Official color palette for nixos-gateway
{
  colors = {
    primaryLight  = "#7EBAE4";
    primaryDark   = "#5277C3";
    bgDarkest     = "#0D131A";
    bgBase        = "#1A2432";
    surfaceSubtle = "#2D3A4C";
    textMain      = "#FFFFFF";
    textMuted     = "#A0ABC0";
  };
  gradients = {
    primaryLinear = "linear-gradient(to bottom right, #7EBAE4, #5277C3)";
    darkLinear    = "linear-gradient(to bottom right, #2D3A4C, #1A2432)";
    bgRadial      = "radial-gradient(circle at center, #1A2432 0%, #0D131A 70%)";
  };
}

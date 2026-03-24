{ pkgs ? import <nixpkgs> {} }:

let
  palette = import ./palette.nix;

  # Fontconfig file that points resvg at Liberation Sans (sans-serif stand-in)
  # so text in the social preview renders correctly in the Nix sandbox.
  fontconf = pkgs.writeText "fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <dir>${pkgs.liberation_ttf}/share/fonts</dir>
      <match target="pattern">
        <test name="family"><string>system-ui</string></test>
        <edit name="family" mode="assign"><string>Liberation Sans</string></edit>
      </match>
      <match target="pattern">
        <test name="family"><string>-apple-system</string></test>
        <edit name="family" mode="assign"><string>Liberation Sans</string></edit>
      </match>
      <match target="pattern">
        <test name="family"><string>sans-serif</string></test>
        <edit name="family" mode="assign"><string>Liberation Sans</string></edit>
      </match>
    </fontconfig>
  '';

  logoSvg = pkgs.writeText "logo.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
      <defs>
        <linearGradient id="nixBlue" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="${palette.colors.primaryLight}"/>
          <stop offset="100%" stop-color="${palette.colors.primaryDark}"/>
        </linearGradient>
        <linearGradient id="nixDark" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="${palette.colors.surfaceSubtle}"/>
          <stop offset="100%" stop-color="${palette.colors.bgBase}"/>
        </linearGradient>
      </defs>
      <polygon points="256,40 440,146 440,366 256,472 72,366 72,146" fill="url(#nixDark)" stroke="url(#nixBlue)" stroke-width="24" stroke-linejoin="round"/>

      <circle cx="256" cy="256" r="48" fill="url(#nixBlue)" />

      <circle cx="256" cy="110" r="28" fill="${palette.colors.primaryLight}" />
      <line x1="256" y1="138" x2="256" y2="208" stroke="url(#nixBlue)" stroke-width="20" stroke-linecap="round"/>

      <circle cx="130" cy="328" r="28" fill="${palette.colors.primaryLight}" />
      <line x1="154" y1="314" x2="214" y2="280" stroke="url(#nixBlue)" stroke-width="20" stroke-linecap="round"/>

      <circle cx="382" cy="328" r="28" fill="${palette.colors.primaryLight}" />
      <line x1="358" y1="314" x2="298" y2="280" stroke="url(#nixBlue)" stroke-width="20" stroke-linecap="round"/>

      <circle cx="256" cy="256" r="140" fill="none" stroke="${palette.colors.primaryLight}" stroke-width="6" stroke-dasharray="15 15" opacity="0.4"/>
    </svg>
  '';

  socialPreviewSvg = pkgs.writeText "social-preview.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" width="1200" height="630">
      <defs>
        <radialGradient id="bg" cx="50%" cy="50%" r="70%">
          <stop offset="0%" stop-color="${palette.colors.bgBase}"/>
          <stop offset="100%" stop-color="${palette.colors.bgDarkest}"/>
        </radialGradient>
        <linearGradient id="nixBlue" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="${palette.colors.primaryLight}"/>
          <stop offset="100%" stop-color="${palette.colors.primaryDark}"/>
        </linearGradient>
        <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
          <path d="M 40 0 L 0 0 0 40" fill="none" stroke="${palette.colors.surfaceSubtle}" stroke-width="1" opacity="0.3"/>
        </pattern>
      </defs>

      <rect width="1200" height="630" fill="url(#bg)"/>
      <rect width="1200" height="630" fill="url(#grid)"/>

      <g transform="translate(120, 150) scale(0.65)">
        <polygon points="256,40 440,146 440,366 256,472 72,366 72,146" fill="${palette.colors.bgBase}" stroke="url(#nixBlue)" stroke-width="24" stroke-linejoin="round"/>
        <circle cx="256" cy="256" r="48" fill="url(#nixBlue)" />
        <circle cx="256" cy="110" r="28" fill="${palette.colors.primaryLight}" />
        <line x1="256" y1="138" x2="256" y2="208" stroke="url(#nixBlue)" stroke-width="20" stroke-linecap="round"/>
        <circle cx="130" cy="328" r="28" fill="${palette.colors.primaryLight}" />
        <line x1="154" y1="314" x2="214" y2="280" stroke="url(#nixBlue)" stroke-width="20" stroke-linecap="round"/>
        <circle cx="382" cy="328" r="28" fill="${palette.colors.primaryLight}" />
        <line x1="358" y1="314" x2="298" y2="280" stroke="url(#nixBlue)" stroke-width="20" stroke-linecap="round"/>
        <circle cx="256" cy="256" r="140" fill="none" stroke="${palette.colors.primaryLight}" stroke-width="6" stroke-dasharray="15 15" opacity="0.4"/>
      </g>

      <text x="500" y="300" font-family="system-ui, -apple-system, sans-serif" font-weight="800" font-size="80" fill="${palette.colors.textMain}" letter-spacing="-1">nixos-gateway</text>
      <text x="505" y="360" font-family="system-ui, -apple-system, sans-serif" font-weight="500" font-size="30" fill="${palette.colors.primaryLight}">Declarative • Scalable • High-Performance</text>
      <text x="505" y="410" font-family="system-ui, -apple-system, sans-serif" font-weight="400" font-size="22" fill="${palette.colors.textMuted}" opacity="0.9">The ultimate enterprise edge routing and security platform</text>
      <text x="505" y="445" font-family="system-ui, -apple-system, sans-serif" font-weight="400" font-size="22" fill="${palette.colors.textMuted}" opacity="0.9">built on NixOS.</text>
    </svg>
  '';

  # Pre-built assets derivation (used internally and by nix build)
  assets = pkgs.runCommand "nixos-gateway-branding-assets"
    { nativeBuildInputs = [ pkgs.resvg pkgs.liberation_ttf ]; }
    ''
      mkdir -p $out/assets

      # SVG originals
      cp ${logoSvg}          $out/assets/logo.svg
      cp ${socialPreviewSvg} $out/assets/social-preview.svg

      # PNG conversions — point resvg at Liberation Sans so sandbox text renders
      export FONTCONFIG_FILE=${fontconf}
      resvg ${logoSvg}          $out/assets/logo.png
      resvg ${socialPreviewSvg} $out/assets/social-preview.png
    '';

in pkgs.writeShellApplication {
  name = "nixos-gateway-branding";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    dest="''${1:-assets}"
    mkdir -p "$dest"
    cp ${assets}/assets/logo.svg        "$dest/logo.svg"
    cp ${assets}/assets/logo.png        "$dest/logo.png"
    cp ${assets}/assets/social-preview.svg "$dest/social-preview.svg"
    cp ${assets}/assets/social-preview.png "$dest/social-preview.png"
    chmod u+w "$dest"/*.svg "$dest"/*.png
    echo "Branding assets written to $dest/"
    echo "  logo.svg           (512x512)"
    echo "  logo.png           (512x512)"
    echo "  social-preview.svg (1200x630)"
    echo "  social-preview.png (1200x630)"
  '';
}

{
  pkgs,
  lib,
}:

let
  # Function to generate options documentation
  generateOptionsDocs =
    {
      modules,
      optionsPath ? [
        "services"
        "gateway"
      ],
      title ? "Gateway Configuration Options",
      description ? "Configuration options for the NixOS Gateway framework",
    }:
    let
      # Create a minimal evaluation of the options
      eval = lib.evalModules {
        modules = modules ++ [
          # Ensure services.gateway is treated as a submodule with options, not a plain attrs
          {
            # No manual options.services.gateway definition here
            # Let the modules define it, or it will conflict
          }
        ];
        specialArgs = { inherit pkgs; };
      };

      # Extract the options at the specified path
      targetOptions = lib.foldl' (acc: key: acc.${key}) eval.options optionsPath;

      # Generate documentation using nixosOptionsDoc
      optionsDoc = pkgs.nixosOptionsDoc {
        options = targetOptions;
        documentType = "none";
        transformOptions =
          opt:
          opt
          // {
            declarations = map (
              d:
              if lib.hasPrefix (toString ../.) (toString d) then
                lib.removePrefix (toString ../.) (toString d)
              else
                d
            ) opt.declarations;
          };
      };
    in
    pkgs.runCommand "gateway-docs" { nativeBuildInputs = [ pkgs.nixos-render-docs ]; } ''
      mkdir -p $out/share/doc/gateway

      # Generate HTML
      nixos-render-docs options html \
        --manpage-urls ${pkgs.path}/doc/manpage-urls.json \
        --revision "unstable" \
        ${optionsDoc.optionsJSON}/share/doc/nixos/options.json \
        $out/share/doc/gateway/index.html

      # Generate Metadata
      cat > $out/share/doc/gateway/metadata.json <<EOF
      {
        "title": "${title}",
        "description": "${description}",
        "generated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      }
      EOF
    '';
in
{
  inherit generateOptionsDocs;
}

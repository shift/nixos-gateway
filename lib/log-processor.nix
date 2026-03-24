{ lib, ... }:

let
  inherit (lib)
    mapAttrsToList
    concatStringsSep
    mkOption
    types
    ;

  # Helper to generate Fluent Bit input sections
  mkFluentBitInput =
    input:
    let
      # Common fields
      baseConfig = {
        Name = input.type or "tail";
        Tag = input.tag;
      }
      // (if input ? path then { Path = input.path; } else { })
      // (
        if input ? maxLines then
          {
            Buffer_Chunk_Size = "512k";
            Buffer_Max_Size = "5M";
          }
        else
          { }
      )
      // (if input ? parser then { Parser = input.parser; } else { })
      // (if input.readFromHead or false then { Read_from_Head = "On"; } else { });

      # Add systemd specific fields
      finalConfig =
        if input.name == "systemd" then
          baseConfig
          // {
            Name = "systemd";
            Path = input.path or "/var/log/journal";
            Systemd_Filter = "_SYSTEMD_UNIT=k3s.service"; # Example default
          }
        else
          baseConfig;

      configStr = concatStringsSep "\n" (mapAttrsToList (k: v: "    ${k} ${toString v}") finalConfig);
    in
    ''
      [INPUT]
      ${configStr}
    '';

  # Helper to generate Fluent Bit filter sections
  mkFluentBitFilter =
    filter:
    let
      baseConfig = {
        Name = filter.name;
        Match = filter.match;
      }
      // (if filter ? keyName then { Key_Name = filter.keyName; } else { })
      // (if filter ? parser then { Parser = filter.parser; } else { });

      # Handle 'enrich' type (usually record_modifier)
      finalConfig =
        if filter.name == "enrich" then
          {
            Name = "record_modifier";
            Match = filter.match;
          }
          // (
            if filter ? add then
              lib.listToAttrs (
                mapAttrsToList (k: v: {
                  name = "Record";
                  value = "${k} ${v}";
                }) filter.add
              )
            else
              { }
          )
        else
          baseConfig;

      configStr = concatStringsSep "\n" (mapAttrsToList (k: v: "    ${k} ${toString v}") finalConfig);
    in
    ''
      [FILTER]
      ${configStr}
    '';

  # Helper to generate Fluent Bit output sections
  mkFluentBitOutput =
    output:
    let
      baseConfig = {
        Name = output.name;
        Match = output.match;
      }
      // (if output ? host then { Host = output.host; } else { })
      // (if output ? port then { Port = toString output.port; } else { })
      // (if output ? index then { Index = output.index; } else { })
      // (if output ? timeKey then { Time_Key = output.timeKey; } else { });

      # Handle elasticsearch specifics
      finalConfig =
        if output.name == "elasticsearch" then
          baseConfig
          // {
            Port = "9200";
            Logstash_Format = "On";
            Replace_Dots = "On";
            Retry_Limit = "False";
          }
        else
          baseConfig;

      configStr = concatStringsSep "\n" (mapAttrsToList (k: v: "    ${k} ${toString v}") finalConfig);
    in
    ''
      [OUTPUT]
      ${configStr}
    '';

  # Helper to generate Parser sections
  mkFluentBitParser =
    name: parser:
    let
      baseConfig = {
        Name = name;
        Format = parser.type; # regex, json, etc.
      }
      // (if parser ? regex then { Regex = parser.regex; } else { })
      // (if parser ? timeKey then { Time_Key = parser.timeKey; } else { })
      // (if parser ? timeFormat then { Time_Format = parser.timeFormat; } else { });

      configStr = concatStringsSep "\n" (mapAttrsToList (k: v: "    ${k} ${toString v}") baseConfig);
    in
    ''
      [PARSER]
      ${configStr}
    '';

in
{
  inherit
    mkFluentBitInput
    mkFluentBitFilter
    mkFluentBitOutput
    mkFluentBitParser
    ;

  # Validation helpers
  validateRetentionPolicy = policy: policy ? match && policy ? retention;

  validateParser = parser: parser ? type && (parser.type == "regex" -> parser ? regex);
}

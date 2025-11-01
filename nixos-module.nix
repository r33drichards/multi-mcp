{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.multi-mcp;

  # Convert Nix attrset to MCP server JSON format
  mcpServerToJson = name: serverCfg:
    let
      base = {
        inherit (serverCfg) command args;
      } // optionalAttrs (serverCfg.env != null) {
        inherit (serverCfg.env);
      } // optionalAttrs (serverCfg.url != null) {
        inherit (serverCfg.url);
      };
    in base;

  # Generate the MCP config JSON file
  mcpConfigFile = pkgs.writeText "mcp-config.json" (builtins.toJSON {
    mcpServers = mapAttrs mcpServerToJson cfg.servers;
  });

in {
  options.services.multi-mcp = {
    enable = mkEnableOption "Multi-MCP proxy server";

    package = mkOption {
      type = types.package;
      default = pkgs.multi-mcp or (throw "multi-mcp package not found. Make sure to add the overlay from the flake.");
      description = "The multi-mcp package to use.";
    };

    transport = mkOption {
      type = types.enum [ "stdio" "sse" ];
      default = "sse";
      description = ''
        Transport mode for the MCP server.
        - stdio: Pipe-based communication for CLI tools
        - sse: HTTP Server-Sent Events for network access
      '';
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host to bind the SSE server (only used when transport is 'sse').";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to bind the SSE server (only used when transport is 'sse').";
    };

    logLevel = mkOption {
      type = types.enum [ "DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL" ];
      default = "INFO";
      description = "Logging level for the multi-mcp server.";
    };

    servers = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          command = mkOption {
            type = types.str;
            description = "Command to execute for this MCP server.";
            example = "python";
          };

          args = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Arguments to pass to the command.";
            example = [ "/path/to/script.py" ];
          };

          env = mkOption {
            type = types.nullOr (types.attrsOf types.str);
            default = null;
            description = "Environment variables for this MCP server.";
            example = { API_KEY = "secret"; };
          };

          url = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "URL for remote SSE-based MCP server.";
            example = "http://127.0.0.1:9080/sse";
          };
        };
      });
      default = {};
      description = ''
        MCP servers to proxy. Each server is defined with a command and args,
        or a URL for remote servers.
      '';
      example = literalExpression ''
        {
          weather = {
            command = "python";
            args = [ "/path/to/weather.py" ];
            env = { API_KEY = "abc123"; };
          };
          github = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-github" ];
            env = { GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_xxx"; };
          };
          remote = {
            url = "http://127.0.0.1:9080/sse";
          };
        }
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to an environment file containing secrets.
        The file should contain KEY=VALUE pairs, one per line.
        This is useful for storing API keys and tokens securely.
      '';
      example = "/run/secrets/multi-mcp-env";
    };

    user = mkOption {
      type = types.str;
      default = "multi-mcp";
      description = "User account under which multi-mcp runs.";
    };

    group = mkOption {
      type = types.str;
      default = "multi-mcp";
      description = "Group under which multi-mcp runs.";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "Multi-MCP service user";
    };

    users.groups.${cfg.group} = {};

    # Create systemd service
    systemd.services.multi-mcp = {
      description = "Multi-MCP Proxy Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = "10s";

        # Load environment variables from file if specified
        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ ];

        ExecStart = ''
          ${cfg.package}/bin/multi-mcp \
            --transport ${cfg.transport} \
            --config ${mcpConfigFile} \
            --host ${cfg.host} \
            --port ${toString cfg.port} \
            --log-level ${cfg.logLevel}
        '';
      };
    };

    # Open firewall port if using SSE transport
    networking.firewall.allowedTCPPorts = mkIf (cfg.transport == "sse") [ cfg.port ];
  };
}

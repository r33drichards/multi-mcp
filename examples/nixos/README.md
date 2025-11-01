# NixOS Module for Multi-MCP

This directory contains examples for using multi-mcp as a NixOS service.

## Quick Start

### 1. Add multi-mcp to your system flake

Add multi-mcp as an input to your NixOS system flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    multi-mcp.url = "github:r33drichards/multi-mcp";
  };

  outputs = { self, nixpkgs, multi-mcp, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        multi-mcp.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Configure the service

In your `configuration.nix`:

```nix
{
  services.multi-mcp = {
    enable = true;
    transport = "sse";
    host = "127.0.0.1";
    port = 8080;

    servers = {
      github = {
        command = "npx";
        args = [ "-y" "@modelcontextprotocol/server-github" ];
        env.GITHUB_PERSONAL_ACCESS_TOKEN = "your-token";
      };
    };
  };
}
```

### 3. Rebuild your system

```bash
sudo nixos-rebuild switch --flake .#myhost
```

## Configuration Options

### `services.multi-mcp.enable`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** Enable the multi-mcp service

### `services.multi-mcp.transport`
- **Type:** `enum ["stdio" "sse"]`
- **Default:** `"sse"`
- **Description:** Transport mode
  - `stdio`: Pipe-based for CLI tools
  - `sse`: HTTP Server-Sent Events for network access

### `services.multi-mcp.host`
- **Type:** `string`
- **Default:** `"127.0.0.1"`
- **Description:** Host to bind (SSE mode only)

### `services.multi-mcp.port`
- **Type:** `port number`
- **Default:** `8080`
- **Description:** Port to bind (SSE mode only)

### `services.multi-mcp.logLevel`
- **Type:** `enum ["DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL"]`
- **Default:** `"INFO"`
- **Description:** Logging verbosity

### `services.multi-mcp.servers`
- **Type:** `attribute set`
- **Default:** `{}`
- **Description:** MCP servers to multiplex

Each server supports:
- `command` (string): Command to execute
- `args` (list of strings): Command arguments
- `env` (attribute set): Environment variables
- `url` (string): Remote SSE server URL (alternative to command)

### `services.multi-mcp.environmentFile`
- **Type:** `null or path`
- **Default:** `null`
- **Description:** Path to environment file for secrets

### `services.multi-mcp.user` / `services.multi-mcp.group`
- **Type:** `string`
- **Default:** `"multi-mcp"`
- **Description:** User/group to run the service

## Examples

### Basic Local Tools

```nix
services.multi-mcp = {
  enable = true;
  servers = {
    calculator = {
      command = "python";
      args = [ "/opt/mcp-tools/calculator.py" ];
    };
    weather = {
      command = "python";
      args = [ "/opt/mcp-tools/weather.py" ];
      env.API_KEY = "abc123";
    };
  };
};
```

### NPX-Based MCP Servers

```nix
services.multi-mcp = {
  enable = true;
  servers = {
    github = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-github" ];
      env.GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_xxx";
    };
    brave-search = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-brave-search" ];
      env.BRAVE_API_KEY = "BSA_xxx";
    };
  };
};
```

### Remote SSE Server

```nix
services.multi-mcp = {
  enable = true;
  servers = {
    remote = {
      url = "http://remote-host:9080/sse";
    };
  };
};
```

### Using Environment Files for Secrets

For production deployments, use an environment file instead of inline secrets:

```nix
services.multi-mcp = {
  enable = true;
  environmentFile = "/run/secrets/multi-mcp-env";
  servers = {
    github = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-github" ];
      # GITHUB_PERSONAL_ACCESS_TOKEN loaded from environmentFile
    };
  };
};
```

Create `/run/secrets/multi-mcp-env`:
```bash
GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxxxxxxxxxxx
BRAVE_API_KEY=BSA_xxxxxxxxxxxx
```

### With sops-nix

```nix
{
  sops.secrets.multi-mcp-env = {
    sopsFile = ./secrets.yaml;
    owner = config.services.multi-mcp.user;
  };

  services.multi-mcp = {
    enable = true;
    environmentFile = config.sops.secrets.multi-mcp-env.path;
    servers = {
      github = {
        command = "npx";
        args = [ "-y" "@modelcontextprotocol/server-github" ];
      };
    };
  };
}
```

## Service Management

### Check service status
```bash
systemctl status multi-mcp
```

### View logs
```bash
journalctl -u multi-mcp -f
```

### Restart service
```bash
sudo systemctl restart multi-mcp
```

## Testing the Service

Once running, you can test the SSE endpoint:

```bash
curl http://localhost:8080/mcp_tools
```

Or use it with Claude Code or other MCP clients by pointing to:
```
http://localhost:8080/sse
```

## Tool Namespacing

Multi-MCP automatically namespaces tools from backend servers using the pattern:
```
mcp__multi-mcp__{server_name}_{tool_name}
```

For example:
- GitHub server's `search_repositories` becomes `mcp__multi-mcp__github_search_repositories`
- Brave server's `brave_web_search` becomes `mcp__multi-mcp__brave-search_brave_web_search`

## Security Considerations

1. **Environment Files:** Use `environmentFile` for secrets, not inline `env` attributes
2. **Firewall:** Port is automatically opened only when `transport = "sse"`
3. **User Isolation:** Service runs as dedicated `multi-mcp` user
4. **Hardening:** Systemd security features enabled (NoNewPrivileges, PrivateTmp, etc.)
5. **Secrets Management:** Consider sops-nix or agenix for production

## Troubleshooting

### Service fails to start
Check logs for errors:
```bash
journalctl -u multi-mcp -n 50
```

### Tools not appearing
Verify MCP server configuration and check that Node.js is available if using npx-based servers.

### Port conflicts
Change the port in configuration:
```nix
services.multi-mcp.port = 8081;
```

## See Also

- [Multi-MCP Documentation](../../README.md)
- [MCP Protocol Specification](https://modelcontextprotocol.io)
- [Example Configurations](../config/)

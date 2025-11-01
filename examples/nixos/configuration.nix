# Example NixOS configuration using the multi-mcp module
#
# This example shows how to configure multi-mcp as a NixOS service
# with multiple MCP backend servers.

{ config, pkgs, ... }:

{
  imports = [
    # Import the multi-mcp flake module in your flake-based config
    # See flake.nix example below for how to add this to your system flake
  ];

  # Enable and configure multi-mcp service
  services.multi-mcp = {
    enable = true;

    # Transport mode: "stdio" for CLI/pipe-based, "sse" for HTTP
    transport = "sse";

    # Network configuration (only used with SSE transport)
    host = "0.0.0.0";  # Bind to all interfaces
    port = 8080;

    # Logging level
    logLevel = "INFO";

    # Define MCP servers to multiplex
    servers = {
      # Example: Local Python-based weather tool
      weather = {
        command = "python";
        args = [ "/path/to/weather.py" ];
        env = {
          WEATHER_API_KEY = "your-api-key-here";
        };
      };

      # Example: GitHub MCP server via npx
      github = {
        command = "npx";
        args = [ "-y" "@modelcontextprotocol/server-github" ];
        env = {
          GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_xxxxxxxxxxxx";
        };
      };

      # Example: Brave Search MCP server
      brave-search = {
        command = "npx";
        args = [ "-y" "@modelcontextprotocol/server-brave-search" ];
        env = {
          BRAVE_API_KEY = "BSAxxxxxxxxxxxx";
        };
      };

      # Example: Context7 documentation server (no auth needed)
      context7 = {
        command = "npx";
        args = [ "-y" "@upstash/context7-mcp" ];
      };

      # Example: Remote SSE-based MCP server
      remote-service = {
        url = "http://remote-host:9080/sse";
      };
    };

    # Optional: Use an environment file for secrets instead of inline env vars
    # This is more secure for production deployments
    # environmentFile = "/run/secrets/multi-mcp-env";

    # Optional: Custom user/group (defaults to multi-mcp)
    # user = "multi-mcp";
    # group = "multi-mcp";
  };

  # The firewall port is automatically opened when transport = "sse"
  # networking.firewall.allowedTCPPorts is set automatically
}

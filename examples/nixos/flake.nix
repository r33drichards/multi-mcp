# Example flake.nix for a NixOS system using multi-mcp
#
# This shows how to integrate multi-mcp into your NixOS configuration
# using flakes.

{
  description = "NixOS system with multi-mcp service";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Add multi-mcp flake as an input
    multi-mcp = {
      url = "github:r33drichards/multi-mcp";
      # Optional: pin to a specific branch/tag
      # url = "github:r33drichards/multi-mcp/main";
    };
  };

  outputs = { self, nixpkgs, multi-mcp, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Import the multi-mcp NixOS module
        multi-mcp.nixosModules.default

        # Your system configuration
        ./configuration.nix

        # Or configure multi-mcp inline:
        {
          services.multi-mcp = {
            enable = true;
            transport = "sse";
            host = "127.0.0.1";
            port = 8080;
            logLevel = "INFO";

            servers = {
              github = {
                command = "npx";
                args = [ "-y" "@modelcontextprotocol/server-github" ];
              };

              brave-search = {
                command = "npx";
                args = [ "-y" "@modelcontextprotocol/server-brave-search" ];
              };
            };

            # Recommended: Use sops-nix or agenix for secrets
            environmentFile = "/run/secrets/multi-mcp-env";
          };
        }
      ];
    };
  };
}

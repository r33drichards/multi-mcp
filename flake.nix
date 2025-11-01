{
  description = "Multi-MCP - A proxy server for multiple MCP backends";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312;

        # Build the application package
        multi-mcp = pkgs.stdenv.mkDerivation {
          pname = "multi-mcp";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          dontBuild = true;

          installPhase = ''
            mkdir -p $out/share/multi-mcp
            mkdir -p $out/bin

            # Copy all source files to share directory
            cp -r src $out/share/multi-mcp/
            cp main.py $out/share/multi-mcp/
            cp requirements.txt $out/share/multi-mcp/
            cp pyproject.toml $out/share/multi-mcp/

            # Copy config examples
            mkdir -p $out/share/multi-mcp/examples
            if [ -d examples/config ]; then
              cp -r examples/config $out/share/multi-mcp/examples/
            fi

            # Create wrapper script
            cat > $out/bin/multi-mcp <<EOF
#!/bin/sh
export UV_PROJECT_ENVIRONMENT="\$HOME/.cache/multi-mcp/venv"
export PATH="${pkgs.lib.makeBinPath [ pkgs.nodejs_20 python pkgs.uv ]}:\$PATH"

# Ensure venv exists and dependencies are installed
if [ ! -f "\$UV_PROJECT_ENVIRONMENT/.deps_installed" ]; then
  cd $out/share/multi-mcp
  ${pkgs.uv}/bin/uv venv --python ${python}/bin/python3 "\$UV_PROJECT_ENVIRONMENT"
  ${pkgs.uv}/bin/uv pip install --python "\$UV_PROJECT_ENVIRONMENT/bin/python" -r requirements.txt
  touch "\$UV_PROJECT_ENVIRONMENT/.deps_installed"
fi

cd $out/share/multi-mcp
exec "\$UV_PROJECT_ENVIRONMENT/bin/python" main.py "\$@"
EOF
            chmod +x $out/bin/multi-mcp
          '';

          meta = with pkgs.lib; {
            description = "Multi-MCP proxy server for routing between multiple MCP backends";
            license = licenses.mit;
            platforms = platforms.unix;
            mainProgram = "multi-mcp";
          };
        };

        # Development shell with uv
        devShell = pkgs.mkShell {
          buildInputs = [
            pkgs.python312
            pkgs.uv
            pkgs.nodejs_20
            pkgs.git
          ];

          shellHook = ''
            echo "Multi-MCP development environment"
            echo "Run 'uv run main.py' to start the server"
          '';
        };

      in
      {
        packages.default = multi-mcp;

        apps.default = {
          type = "app";
          program = "${multi-mcp}/bin/multi-mcp";
        };

        devShells.default = devShell;
      }
    );
}

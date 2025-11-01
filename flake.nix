{
  description = "Multi-MCP - A proxy server for multiple MCP backends";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, pyproject-nix, uv2nix, pyproject-build-systems }:
    let
      # NixOS module (system-independent)
      nixosModule = { config, lib, pkgs, ... }: {
        imports = [ ./nixos-module.nix ];
        # Provide the multi-mcp package via an overlay
        nixpkgs.overlays = lib.mkIf config.services.multi-mcp.enable [
          (final: prev: {
            multi-mcp = self.packages.${prev.system}.default;
          })
        ];
      };
    in
    {
      # NixOS module
      nixosModules.default = nixosModule;
      nixosModules.multi-mcp = nixosModule;
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312;

        # Load uv workspace and create overlays
        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

        # Production overlay using wheel binaries for faster builds
        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };

        # Editable overlay for development
        editableOverlay = workspace.mkEditablePyprojectOverlay {
          root = "$REPO_ROOT";
        };

        # Base Python package set
        baseSet = pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        };

        # Production Python set with all dependencies
        pythonSet = baseSet.overrideScope (
          pkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
          ]
        );

        # Development Python set with editable packages
        devPythonSet = baseSet.overrideScope (
          pkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            editableOverlay
          ]
        );

        # Create production virtual environment
        venv = pythonSet.mkVirtualEnv "multi-mcp-env" workspace.deps.default;

        # Create development virtual environment with all dependencies including dev deps
        devVenv = devPythonSet.mkVirtualEnv "multi-mcp-dev-env" workspace.deps.all;

        # Build the application package with native Python dependencies
        multi-mcp = pkgs.stdenv.mkDerivation {
          pname = "multi-mcp";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          dontBuild = true;

          installPhase = ''
            mkdir -p $out/share/multi-mcp
            mkdir -p $out/bin

            # Copy source files
            cp -r src $out/share/multi-mcp/
            cp main.py $out/share/multi-mcp/
            cp pyproject.toml $out/share/multi-mcp/

            # Copy config examples
            mkdir -p $out/share/multi-mcp/examples
            if [ -d examples/config ]; then
              cp -r examples/config $out/share/multi-mcp/examples/
            fi

            # Create wrapper that uses the Nix-built virtualenv
            makeWrapper ${venv}/bin/python $out/bin/multi-mcp \
              --add-flags "$out/share/multi-mcp/main.py" \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nodejs_20 ]} \
              --chdir "$out/share/multi-mcp"
          '';

          meta = with pkgs.lib; {
            description = "Multi-MCP proxy server for routing between multiple MCP backends";
            license = licenses.mit;
            platforms = platforms.unix;
            mainProgram = "multi-mcp";
          };
        };

      in
      {
        packages.default = multi-mcp;

        apps.default = {
          type = "app";
          program = "${multi-mcp}/bin/multi-mcp";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            devVenv
            pkgs.uv
            pkgs.nodejs_20
            pkgs.git
          ];

          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = devPythonSet.python.interpreter;
            UV_PYTHON_DOWNLOADS = "never";
          };

          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT=$(git rev-parse --show-toplevel)
            echo "Multi-MCP development environment"
            echo "Python: ${python.version}"
            echo "Run 'uv run main.py' to start the server"
          '';
        };
      }
    );
}

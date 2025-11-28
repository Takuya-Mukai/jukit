{
  description = "A development environment for a Python project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11"; # 安定版のブランチを指定

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      pythonEnvironment = pkgs.python3.withPackages (
        ps: with ps; [
          matplotlib
        ]
      );

    in
    {
      # 開発シェルを定義
      devShells.${system}.default = pkgs.mkShell {
        # 環境に含めるNixパッケージ（Pythonインタープリタや他のツールなど）
        buildInputs = [
          pythonEnvironment # 上で定義したPython環境
        ];

        # シェルがロードされたときに実行されるフック
        shellHook = ''
          # echo "Python development environment loaded (Python 3.11)."
        '';
      };
    };
}

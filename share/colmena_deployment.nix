{ hosts, channels }:

let
  inherit (import channels) pkgs;

  channelsFile = pkgs.writeText "channels.nix" (builtins.readFile channels);

  deployment_name = "terramena";

  moduleFiles = pkgs.stdenv.mkDerivation {
    name = "module_files";

    src = ./.;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out

      cp ${channelsFile} $out/
      cp -r $src/* $out/
    '';
  };

  host_file = pkgs.writeText "${deployment_name}_deployment_hosts.json" ''
    ${hosts}
  '';
in
pkgs.writeText "${deployment_name}_deployment.nix" ''
  let
    inherit (import "${channelsFile}") pkgs unstable;
    lib = pkgs.lib;

    hostConfig = host: lib.setAttrByPath [ host.hostname ] (import ("${moduleFiles}/" + host.configuration) {
      keys = host.keys;
      node = {
        inherit (host) id ip private_ip public_ip hostname tags region availability_zone;
      };
      inherit pkgs unstable;
    });

    recursiveMergeAttrs = listOfAttrsets: lib.fold (attrset: acc: lib.recursiveUpdate attrset acc) {} listOfAttrsets;

    hosts = builtins.fromJSON (builtins.readFile ${host_file});
  in
  recursiveMergeAttrs ([{
      meta = {
        nixpkgs = pkgs;
      };
  }] ++ (map hostConfig hosts))
''

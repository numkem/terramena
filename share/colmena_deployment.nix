{ hosts, channels }:

let
  inherit (import channels) pkgs;

  channelFileContent = builtins.readFile channels;

  deployment_name = "terramena";

  moduleFiles = pkgs.stdenv.mkDerivation {
    name = "module_files";

    src = ./.;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out

      cp -r $src/* $out/
      rm -vf $out/channels.nix

      cat >$out/channels.nix <<EOF
      ${channelFileContent}
      EOF
    '';
  };

  host_file = pkgs.writeText "${deployment_name}_deployment_hosts.json" ''
    ${hosts}
  '';
in
pkgs.writeText "${deployment_name}_deployment.nix" ''
  let
    inherit (import "${moduleFiles}/channels.nix") pkgs unstable;
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

# Terramena

Terramena is a bridge between[Terraform](https://www.terraform.io) and [Colmena](https://github.com/zhaofengli/colmena).

## Usage

There are multiple ways to use terramena.

### Running from a git clone

``` shell
$ git clone https://github.com/numkem/terramena.git
```

Once that's done, you can use it from a Terraform's deployment directory by calling the executable (say it would be in `~/src/terramena`):

``` shell
$ ~/src/terramena/bin/terramena [...]
```

### With Nix/NixOS

This repository is a flake so you can add it to the current devShell directly.

``` nix
{
  inputs.terramena.url = github:numkem/terramena;
  
  outputs = { self, nixpkgs, terramena, ... }: {
    devShells.x86_64-linux.default = with import nixpkgs { system = "x86_64-linux"; }; pkgs.mkShell {
        buildInputs = [
        terramena.packages.x86_64-linux.default
        ];
    };
  };
}
```

There are millions of ways to make this work. The above method is just one of them.

## How does it work?

Terramena works by analyzing the terraform outputs from a deployment to look for a map that contains a key/value of `_type`/`NixOS_host`.

A Terraform module is available [here](https://github.com/numkem/terramena/tree/main/terraform/modules). This is only an example but it's been known to work very well in production.

### Something to remember

Don't forget to put the output of the terraform module as an output!

## Capabilities

Various commands can be given as first argument to the script.

### deploy

You can deploy NixOS configurations on hosts using this command, the script will build a temporary directory than will copy all the required files to it before calling nix to build a colmena deployment file. Once the build finishes colmena gets executed.

### list

Lists all the NixOS hosts found in the terraform deployment.

### ssh

You can connect to a NixOS host by name using this command, no need to remember the IP address.

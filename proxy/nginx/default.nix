{ config, pkgs, lib, ... }:
let
  rules = import ../../rules.nix;

  # from https://stackoverflow.com/a/54505212
  recursiveMerge = with lib;
    attrList:
    let
      f = attrPath:
        zipAttrsWith (n: values:
          if tail values == [ ] then
            head values
          else if all isList values then
            unique (concatLists values)
          else if all isAttrs values then
            f (attrPath ++ [ n ]) values
          else
            last values);
    in f [ ] attrList;

  rulesConvertedToNginxConfig = recursiveMerge (map (rule:
    if builtins.hasAttr "redirect" rule then {
      virtualHosts."${rule.redirect}" = {
        locations."/".return =
          "302 ${rule.dest}${if rule ? "stripURI" then "" else "$request_uri"}";
      };
    } else if builtins.hasAttr "permRedirect" rule then {
      virtualHosts."${rule.permRedirect}" = {
        locations."/".return = "301 ${rule.dest}$request_uri";
      };
    } else if builtins.hasAttr "proxy" rule then {
      virtualHosts."${rule.proxy}" = {
        locations."/" = {
          proxyPass = "${rule.dest}$request_uri";
          proxyWebsockets = true;
          extraConfig = ''
            # required when the destination is also a TLS server with multiple hosts
            proxy_ssl_server_name on;

            # pass through the client's IP
            proxy_set_header X-Real-IP $remote_addr;
          '';
        };
      };
    } else
      abort "Can't find 'proxy', 'redirect', or 'permRedirect' in ${
        builtins.toJSON rule
      }") rules);
in {
  networking.firewall.allowedTCPPorts = [ 80 ];

  services.nginx = {
    enable = builtins.trace (builtins.toJSON rulesConvertedToNginxConfig) true;

    resolver = { addresses = [ "1.1.1.1" ]; };
  } // rulesConvertedToNginxConfig;
}

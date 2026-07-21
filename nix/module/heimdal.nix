{
  pkgs,
  config,
  lib,
  ...
}:

let
  inherit (lib) mapAttrs;
  cfg = config.services.kerberos_server;
  package = config.security.krb5.package;

  socketActivation = cfg.enableSocketActivation;

  serviceWantedBy = [ "kerberos-server.target" ];

  aclConfigs = lib.pipe cfg.settings.realms [
    (mapAttrs (
      name:
      { acl, ... }:
      lib.concatMapStringsSep "\n" (
        {
          principal,
          access,
          target,
          ...
        }:
        "${principal}\t${lib.concatStringsSep "," (lib.toList access)}\t${target}"
      ) acl
    ))
    (lib.mapAttrsToList (
      name: text: {
        dbname = "/var/lib/heimdal/heimdal";
        acl_file = pkgs.writeText "${name}.acl" text;
      }
    ))
  ];

  finalConfig = cfg.settings // {
    realms = mapAttrs (_: v: removeAttrs v [ "acl" ]) (cfg.settings.realms or { });
    kdc = (cfg.settings.kdc or { }) // {
      database = aclConfigs;
    };
  };

  format = import ./krb5-conf-format.nix { inherit pkgs lib; } {
    enableKdcACLEntries = true;
  };

  kdcConfFile = format.generate "kdc.conf" finalConfig;
in

{
  config = lib.mkIf (cfg.enable && package.passthru.implementation == "heimdal") {
    environment.etc."heimdal-kdc/kdc.conf".source = kdcConfFile;

    systemd.tmpfiles.settings."10-heimdal" =
      let
        databases = lib.pipe finalConfig.kdc.database [
          (map (dbAttrs: dbAttrs.dbname or null))
          (lib.filter (x: x != null))
          lib.unique
        ];
      in
      lib.genAttrs databases (_: {
        d = {
          user = "root";
          group = "root";
          mode = "0700";
        };
      });

    systemd.services.kadmind = {
      description = "Kerberos Administration Daemon";
      partOf = [ "kerberos-server.target" ];
      wantedBy = serviceWantedBy;
      serviceConfig = {
        Type = "notify";
        ExecStart = "${package}/libexec/kadmind --config-file=/etc/heimdal-kdc/kdc.conf";
        Slice = "system-kerberos-server.slice";
        StateDirectory = "heimdal";

        PrivateNetwork = socketActivation;
      };
      restartTriggers = [ kdcConfFile ];
    };

    systemd.services.kdc = {
      description = "Key Distribution Center daemon";
      partOf = [ "kerberos-server.target" ];
      wantedBy = serviceWantedBy;
      serviceConfig = {
        Type = "notify";
        ExecStart = "${package}/libexec/kdc --config-file=/etc/heimdal-kdc/kdc.conf";
        Slice = "system-kerberos-server.slice";
        StateDirectory = "heimdal";
        PrivateNetwork = socketActivation;
      };
      restartTriggers = [ kdcConfFile ];
    };

    systemd.services.kpasswdd = {
      description = "Kerberos Password Changing daemon";
      partOf = [ "kerberos-server.target" ];
      wantedBy = serviceWantedBy;
      serviceConfig = {
        Type = "notify";
        ExecStart = "${package}/libexec/kpasswdd";
        Slice = "system-kerberos-server.slice";
        StateDirectory = "heimdal";
        PrivateNetwork = socketActivation;
      };
      restartTriggers = [ kdcConfFile ];
    };

    systemd.sockets = lib.mkIf socketActivation {
      kadmind = {
        description = "Kerberos Administration Daemon socket";
        partOf = [ "kerberos-server.target" ];
        wantedBy = [
          "sockets.target"
          "kerberos-server.target"
        ];
        socketConfig = {
          ListenStream = 749;
          FileDescriptorName = "kadmind";
          Accept = false;
          Slice = "system-kerberos-server.slice";
        };
      };

      kdc = {
        description = "Key Distribution Center daemon socket";
        partOf = [ "kerberos-server.target" ];
        wantedBy = [
          "sockets.target"
          "kerberos-server.target"
        ];
        socketConfig = {
          ListenStream = 88;
          ListenDatagram = 88;
          FileDescriptorName = "kdc";
          Accept = false;
          Slice = "system-kerberos-server.slice";
        };
      };

      kpasswdd = {
        description = "Kerberos Password Changing daemon socket";
        partOf = [ "kerberos-server.target" ];
        wantedBy = [
          "sockets.target"
          "kerberos-server.target"
        ];
        socketConfig = {
          ListenDatagram = 464;
          FileDescriptorName = "kpasswdd";
          Accept = false;
          Slice = "system-kerberos-server.slice";
        };
      };
    };
  };
}

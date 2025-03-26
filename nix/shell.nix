{ pkgs, lib }:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    autoconf
    automake
    autogen
    autoreconfHook

    pkg-config
    python3
    perl
    bison
    flex
    perlPackages.JSON
    texinfo

    # check inputs
    curl
    jdk_headless
    unzip
    which
  ];

  buildInputs = with pkgs; [
    db
    libedit
    pam
    cjson
    libcap_ng
    libmicrohttpd
    openldap
    openssl
    sqlite
  ];

  env = {
    CFLAGS = lib.concatStringsSep " " [
      # From github workflows
      "-Wno-error=shadow"
      "-Wno-error=bad-function-cast"
      "-Wno-error=unused-function"
      "-Wno-error=unused-result"
      "-Wno-error=deprecated-declarations"

      # idk, but it complained about these during compilation.
      # maybe they come from the nix environment, or too new compiler?
      "-Wno-error=maybe-uninitialized"
      "-Wno-error=format-overflow"
    ];
  };
}

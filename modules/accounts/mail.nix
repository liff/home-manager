{ config, lib, ... }:

with lib;

let

  cfg = config.accounts.mail;
  dag = config.lib.dag;

  tlsModule = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable TLS/SSL.
        '';
      };

      useStartTls = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to use STARTTLS.
        '';
      };

      certificatesFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to file containing certificate authorities that should
          be used to validate the connection authenticity. If
          <literal>null</literal> then the system default is used.
          Note, if set then the system default may still be accepted.
        '';
      };
    };
  };

  imapModule = types.submodule {
    options = {
      host = mkOption {
        type = types.str;
        example = "imap.example.org";
        description = ''
          Hostname of IMAP server.
        '';
      };

      port = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        example = 993;
        description = ''
          The port on which the IMAP server listens. If
          <literal>null</literal> then the default port is used.
        '';
      };

      tls = mkOption {
        type = tlsModule;
        default = {};
        description = ''
          Configuration for secure connections.
        '';
      };
    };
  };

  smtpModule = types.submodule {
    options = {
      host = mkOption {
        type = types.str;
        example = "smtp.example.org";
        description = ''
          Hostname of SMTP server.
        '';
      };

      port = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        example = 465;
        description = ''
          The port on which the SMTP server listens. If
          <literal>null</literal> then the default port is used.
        '';
      };

      tls = mkOption {
        type = tlsModule;
        default = {};
        description = ''
          Configuration for secure connections.
        '';
      };
    };
  };

  maildirModule = types.submodule {
    options = {
      path = mkOption {
        type = types.nullOr types.path;
        defaultText = "$MAILDIR/\${name}";
        description = ''
          Path to Maildir directory where mail for this account is
          stored.
        '';
      };
    };
  };

  # gpgModule = types.submodule {
  # };

  mailAccount = types.submodule ({ name, config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          Unique identifier of the account. This is set to the
          attribute name of the account configuration.
        '';
      };

      primary = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether this is the primary account. Only one account may be
          set as primary.
        '';
      };

      flavor = mkOption {
        type = types.enum [ "standard" "runbox.com" ];
        default = "standard";
        description = ''
          Some email providers have peculiar behavior that require
          special treatment. This option is therefore intended to
          indicate the nature of the provider.
          </para><para>
          When this indicates a specific provider then the IMAP and
          SMTP server configuration may be set automatically.
        '';
      };

      address = mkOption {
        type = types.strMatching ".*@.*";
        example = "me@example.org";
        description = "The email address of this account.";
      };

      realName = mkOption {
        type = types.str;
        example = "Jane Doe";
        description = "Name displayed when sending mails.";
      };

      userName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The server username of this account. This will be used as
          the SMTP and IMAP user name.
        '';
      };

      passwordCommand = mkOption {
        type = types.nullOr (types.either types.str (types.listOf types.str));
        default = null;
        apply = p: if isString p then splitString " " p else p;
        example = [ "secret-tool" "lookup" "email" "me@example.org" ];
        description = ''
          A command, which when run writes the account password on
          standard output.
        '';
      };

      imap = mkOption {
        type = types.nullOr imapModule;
        default = null;
        description = ''
          The IMAP configuration to use for this account.
        '';
      };

      smtp = mkOption {
        type = types.nullOr smtpModule;
        default = null;
        description = ''
          The SMTP configuration to use for this account.
        '';
      };

      maildir = mkOption {
        type = types.nullOr maildirModule;
        default = null;
        description = ''
          Path to Maildir directory where mail for this account is
          stored.
        '';
      };

      postSyncHook = mkOption {
        default = types.lines;
        description = "Commands to run after performing a sync.";
      };
    };

    config = mkMerge [
      {
        name = name;

        maildir.path = mkOptionDefault "${cfg.maildirBasePath}/${name}";

        # imap.userName = mkIf (!config.userName) (
        #   mkOptionDefault config.userName
        # );

        # imap.passwordCommand = mkIf (!config.passwordCommand) (
        #   mkOptionDefault config.passwordCommand
        # );
      }

      (mkIf (config.flavor == "runbox.com") {
        imap = {
          host = "mail.runbox.com";
        };

        smtp = {
          host = "mail.runbox.com";
        };
      })
    ];
  });

in

{
  options.accounts.mail = {
    enable = mkEnableOption "email account management";

    maildirBasePath = mkOption {
      type = types.path;
      default = config.home.homeDirectory + "/Maildir";
      defaultText = "$HOME/Maildir";
      description = ''
        The base directory for account maildir directories.
      '';
    };

    accounts = mkOption {
      type = types.attrsOf mailAccount;
      default = {};
      description = "List of email accounts.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      (
        let
          primaries =
            catAttrs "name"
            (filter (a: a.primary)
            (attrValues cfg.accounts));
        in
          {
            assertion = length primaries == 1;
            message =
              "Must have exactly one primary mail account but found "
              + toString (length primaries)
              + optionalString (length primaries > 1)
                  (", namely " + concatStringsSep ", " primaries);
          }
      )
    ];

    # accounts = mkIf (length cfg.accounts == 1) (
    #   let
    #     update = a: recursiveUpdate a { primary = true; };
    #   in
    #     map update cfg.accounts
    # );

    home.sessionVariables.MAILDIR = cfg.maildir;

    home.activation.createMaildir =
      dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -m700 -p $VERBOSE_ARG ${
          concatMapStringsSep " " (a: a.maildir.path) (attrValues cfg.accounts)
        }
      '';
  };
}

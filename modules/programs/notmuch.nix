{ config, lib, pkgs, ... }:

with lib;

let

  dag = config.lib.dag;

  cfg = config.programs.notmuch;

  # # best to  so that tags can use it
  # postSyncCommand = account:
  #   ''
  #     # we export so that hooks use the correct DB
  #     # (not sure it would work with --config)
  #     export NOTMUCH_CONFIG=${getNotmuchConfig account}
  #     ${pkgs.notmuch}/bin/notmuch new
  #   '';

  mkIniKeyValue = key: value:
    let
      tweakVal = v:
        if isString v then v
        else if isList v then concatMapStringsSep ";" tweakVal v
        else if isBool v then toJSON v
        else toString v;
    in
      "${key}=${tweakVal value}";

  notmuchIni = {
    database = {
      path = config.accounts.mail.maildirBasePath;
    };

    new = {
      ignore = cfg.new.ignore;
      tags = cfg.new.tags;
    };

    user = {
      name =
        catAttrs "realName"
        (filter (a: a.primary)
        (attrValues config.accounts.mail.accounts));
      primary_email =
        catAttrs "address"
        (filter (a: a.primary)
        (attrValues config.accounts.mail.accounts));
      other_email =
        catAttrs "address"
        (filter (a: !a.primary)
        (attrValues config.accounts.mail.accounts));
    };

    search = {
      exclude_tags = [ "deleted" "spam" ];
    };
  };

  # # accepts both user.name = ... or [user] name=...
  # genAccountStr = name: account:
  #   ''
  #   [user]
  #   name=${userName}
  #   primary_email=${address}

  #   # TODO move that to extraConfig
  #   [new]
  #   tags=unread;inbox;
  #   ignore=

  #   [search]
  #   exclude_tags=deleted;spam;

  # '';

  extraConfigStr = entries: concatStringsSep "\n" (
    mapAttrsToList (key: val: "${key} = ${val}") entries
  );

  # # TODO run notmuch new instead ?
  # configFile = mailAccount:
  # ''
  #     [database]
  #     # todo make it configurable
  #     path=${getStore mailAccount}

  #     ${accountStr mailAccount}
  # ''
  # + extraConfigStr cfg.extraConfig
  # ;

in

{
  options = {
    programs.notmuch = {
      enable = mkEnableOption "Notmuch mail indexer";

      # # rename getHooksFolder
      # getHooksFolder = mkOption {
      #   # type = types.nullOr types.path; # precise a folder ?
      #   # type = types.function;
      #   default = null;
      #   # account: account.store.".notmuch/hooks";
      #   description = "path to the hooks folder to use for a specific account";
      # };

      new = mkOption {
        type = types.submodule {
          options = {
            ignore = mkOption {
              type = types.listOf types.str;
              default = [];
              description = ''
                A list to specify files and directories that will not be
                searched for messages by <command>notmuch new</command>.
              '';
            };

            tags = mkOption {
              type = types.listOf types.str;
              default = [ "unread" "inbox" ];
              example = [ "new" ];
              description = ''
                A list of tags that will be added to all messages
                incorporated by <command>notmuch new</command>.
              '';
            };
          };
        };
        default = {};
        description = ''
          Options related to email processing performed by
          <command>notmuch new</command>.
        '';
      };

      # postSyncHook = mkOption {
      #   default = postSyncCommand;
      #   description = "Command to run after MRA";
      # };

      extraConfig = mkOption {
        # attr of attrs ?
        type = types.attrsOf (types.attrsOf types.str);
        default = {
          maildir = { synchronize_flags = "True"; };
        };
        description = ''
          Options that should be appended to the notmuch configuration file.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.notmuch ];

    home.sessionVariables = {
      NOTMUCH_CONFIG = "${config.xdg.configHome}/notmuch/notmuchrc";
      NMBGIT = "${config.xdg.dataHome}/notmuch/nmbug";
    };

    xdg.configFile."notmuch/notmuchrc".text =
      let
        toIni = generators.toINI { mkKeyValue = mkIniKeyValue; };
      in
        toIni notmuchIni + "\n\n" + toIni cfg.extraConfig;

    # home.activation.createNotmuchHooks =
    # let
    #   # for now we don't wrap them and instead NOTMUCH_CONFIG
    #   wrapHook = account: ''
    #     mkdir -p ${getStore account}/.notmuch/hooks
    #     ''
    #     + lib.optionalString  (account.configStore != null) ''
    # # buildInputs = [makeWrapper];
    #       # source ${pkgs.makeWrapper}/nix-support/setup-hook

    #     for hookName in post-new pre-new post-insert
    #     do
    #       originalHook=${account.configStore}/$hookName
    #       # mauvaise destination ?
    #       destHook=${getStore account}/.notmuch/hooks/$hookName
    #       echo "If hook $originalHook exists, create [$destHook] wrapper"
    #       if [ -f "$originalHook" ] && [ ! -f "$destHook" ]; then
    #         ln -s "$originalHook" "$destHook"
    #         # makeWrapper "$originalHook"  "$destHook" --set NOTMUCH_CONFIG "${getNotmuchConfig account}"
    #       fi

    #     done
    # '';
    # in 
    # dagEntryAfter [ "createMailStores" ] (
    #   concatStrings  (map wrapHook config.mail.accounts) 
    # );


    # TODO target the hookFolder
    # xdg.homeFile = map (account: {
    #   config.mail.accounts) 
    # }) 

    # Hooks  are  scripts  (or arbitrary executables or symlinks to such) that notmuch invokes before and after certain actions. These scripts reside in the .notmuch/hooks
      # directory within the database directory and must have executable permissions 
    # xdg.configFile = map (account: {
    #   target = "notmuch/notmuch_${account.name}";
    #   text = configFile account; 
    # }) top.config.mail.accounts;
  };
}

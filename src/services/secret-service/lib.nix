{ lib, pkgs }:

let
  inherit (builtins)
    attrNames
    concatMap
    elem
    filter
    hasAttr
    head
    isAttrs
    isPath
    isString
    length
    map
    removeAttrs
    sort
    tail
    ;

  inherit (lib)
    concatStringsSep
    hasInfix
    hasPrefix
    optional
    optionalString
    removePrefix
    unique
    ;

  ageKeygen = "${pkgs.age}/bin/age-keygen";
  keepassxc = "${pkgs.keepassxc}/bin/keepassxc-cli";
  sshKeygen = "${pkgs.openssh}/bin/ssh-keygen";
  sshToAge = "${pkgs.ssh-to-age}/bin/ssh-to-age";

  keepassPasswordCommand =
    keepass:
    if keepass.passwordFile != null then
      "cat ${lib.escapeShellArg (toString keepass.passwordFile)}"
    else if keepass.passwordCommand != null then
      keepass.passwordCommand
    else
      "";

  keepassKeyFileArg =
    keepass:
    optionalString (keepass.keyFilePath != null) (
      "--key-file ${lib.escapeShellArg (toString keepass.keyFilePath)}"
    );

  keepassExtractCommand =
    keepass:
    if keepass.databasePath == null || keepass.entry == null then
      throw "secret-service: keepass.databasePath and keepass.entry are required"
    else
      let
        password = keepassPasswordCommand keepass;
        args =
          "${keepassKeyFileArg keepass} ${lib.escapeShellArg (toString keepass.databasePath)} ${lib.escapeShellArg keepass.entry}";
      in
      if password == "" then
        "${keepassxc} show -q -s -a Password ${args}"
      else
        "printf '%s\\n' \"$(${password})\" | ${keepassxc} show -q -s -a Password ${args}";

  serviceOf = clusterConfig: clusterConfig.clusters.this.services.secrets;
  machineOf = clusterConfig: clusterConfig.clusters.this.machines.this;
  clusterNameOf = clusterConfig: clusterConfig.clusters.this.name;
  machineNameOf = clusterConfig: clusterConfig.clusters.this.machines.this.name;

  isAbsolute = hasPrefix "/";

  sopsRootSpec =
    service:
    if isPath service.sopsRoot then
      {
        nixPath = toString service.sopsRoot;
        osPath = null;
      }
    else
      {
        nixPath = toString service.sopsRoot.nixPath;
        osPath = service.sopsRoot.osPath;
      };

  sopsRootPath = service: (sopsRootSpec service).nixPath;
  sopsRootOsPath = service: (sopsRootSpec service).osPath;

  clusterRootAt =
    root: clusterName:
    if root == "" then clusterName else "${root}/${clusterName}";

  clusterRoot = service: clusterName: clusterRootAt (sopsRootPath service) clusterName;
  clusterRootCommand = service: clusterName: clusterRootAt "" clusterName;

  machineSopsFileAt =
    root: service: clusterName: machineName:
    "${clusterRootAt root clusterName}/${service.machinesSubDir}/${machineName}.yaml";

  clusterSopsFileAt =
    root: explicit: service: clusterName:
    if service.clusterSopsFile != null then
      explicit service.clusterSopsFile
    else
      "${clusterRootAt root clusterName}/cluster.yaml";

  groupSopsFileAt =
    root: service: clusterName: group:
    "${clusterRootAt root clusterName}/${service.clusterSubDir}/${group}.yaml";

  resolveSopsFileAt =
    {
      root,
      explicit,
      service,
      clusterName,
      machineName ? null,
      scope,
      value ? null,
    }:
    let
      defaultValue = if scope == "machine" then "machine" else "cluster";
      selected = if value == null then defaultValue else value;
    in
    if selected == "machine" then
      if machineName == null then
        throw "secret-service: sopsFile = \"machine\" requires a machine scope"
      else
        machineSopsFileAt root service clusterName machineName
    else if selected == "cluster" then
      clusterSopsFileAt root explicit service clusterName
    else if isString selected && hasPrefix "cluster/" selected then
      let
        group = removePrefix "cluster/" selected;
      in
      if group == "" || hasInfix "/" group then
        throw "secret-service: invalid group sopsFile '${selected}'"
      else
        groupSopsFileAt root service clusterName group
    else if isString selected then
      explicit selected
    else
      throw "secret-service: unsupported sopsFile value '${toString selected}'";

  resolveSopsFile =
    args:
    resolveSopsFileAt (
      args
      // {
        root = sopsRootPath args.service;
        explicit = (value: if isAbsolute value then value else "${sopsRootPath args.service}/${value}");
      }
    );

  resolveSopsFileCommand =
    args:
    resolveSopsFileAt (
      args
      // {
        root = "";
        explicit = (value: value);
      }
    );

  secretSopsFile =
    args:
    resolveSopsFile (
      removeAttrs args [ "secret" ]
      // {
        value = args.secret.sopsFile or null;
      }
    );

  secretSopsFileCommand =
    args:
    resolveSopsFileCommand (
      removeAttrs args [ "secret" ]
      // {
        value = args.secret.sopsFile or null;
      }
    );

  keepassEntry =
    {
      clusterName,
      machineName,
      keepass,
    }:
    if keepass.entry != null then
      keepass.entry
    else
      "clusterConfig/${clusterName}/machines/${machineName}";

  # A cluster secret that points at a secret-group file is only visible to
  # members of that secret group. Secret groups are cluster-local access
  # groups; they are unrelated to OS users/groups.
  clusterSecretVisibleToMachine =
    {
      service,
      machineName,
      secret,
    }:
    let
      value = secret.sopsFile or null;
    in
    if value != null && isString value && hasPrefix "cluster/" value then
      let
        group = removePrefix "cluster/" value;
      in
      if group == "" || hasInfix "/" group then
        # Invalid group shorthands are rejected by resolveSopsFileAt.
        true
      else if !(hasAttr group (service.groups or { })) then
        throw "secret-service: sopsFile '${value}' references undefined secret group '${group}'"
      else
        elem machineName (service.groups.${group} or [ ])
    else
      true;

  # Returns the node names selected by the service. Different evaluation stages
  # expose selectors either as filter-produced names or as resolved node sets.
  selectedNodes =
    service:
    unique (
      map
        (
          node:
          if isAttrs node then
            node.name or (throw "secret-service: selector entry has no name")
          else
            node
        )
        (service.selectors or [ ])
    );

  nodeByName =
    clusterConfig: nodeName:
    let
      cluster = clusterConfig.clusters.this;
    in
    if hasAttr nodeName (cluster.machines or { }) then
      cluster.machines.${nodeName}
    else if hasAttr nodeName (cluster.vms or { }) then
      cluster.vms.${nodeName}
    else
      null;

  keySourceOf =
    node:
    if node == null then
      null
    else
      node.deployment.secrets.keySource or null;

  keySourceEnv =
    keySource:
    if keySource == null then
      ""
    else if keySource.type == "age" then
      if keySource.age.sourceKeyFile == null then
        throw "secret-service: age.sourceKeyFile is required for type = \"age\""
      else
        "export SOPS_AGE_KEY_FILE=${lib.escapeShellArg (toString keySource.age.sourceKeyFile)}"
    else if keySource.type == "keepass" then
      ''
        __secret_service_key_file="$(mktemp)"
        trap 'rm -f "$__secret_service_key_file"' EXIT
        ${keepassExtractCommand keySource.keepass} > "$__secret_service_key_file"
        export SOPS_AGE_KEY_FILE="$__secret_service_key_file"
      ''
    else if keySource.type == "ssh" then
      let
        keys = keySource.ssh.keyPaths;
      in
      if keys == [ ] then
        throw "secret-service: ssh.keyPaths must contain at least one key"
      else
        "export SOPS_AGE_SSH_PRIVATE_KEY_FILE=${lib.escapeShellArg (toString (head keys))}"
    else
      "";

  keySourcePublicKeyCommand =
    keySource:
    if keySource == null then
      ""
    else if keySource.type == "age" then
      if keySource.age.sourceKeyFile == null then
        throw "secret-service: age.sourceKeyFile is required for type = \"age\""
      else
        "${ageKeygen} -y ${lib.escapeShellArg (toString keySource.age.sourceKeyFile)}"
    else if keySource.type == "keepass" then
      if keySource.keepass.databasePath == null || keySource.keepass.entry == null then
        throw "secret-service: keepass.databasePath and keepass.entry are required for type = \"keepass\""
      else
      ''
        __secret_service_key="$(mktemp)"
        ${keepassExtractCommand keySource.keepass} > "$__secret_service_key"
        ${ageKeygen} -y "$__secret_service_key"
        rm -f "$__secret_service_key"
      ''
    else if keySource.type == "ssh" then
      let
        keys = keySource.ssh.keyPaths;
      in
      if keys == [ ] then
        throw "secret-service: ssh.keyPaths must contain at least one key"
      else
        "${sshKeygen} -y -f ${lib.escapeShellArg (toString (head keys))} | ${sshToAge}"
    else if keySource.type == "native" then
      if keySource.native.publicKey != null then
        "printf '%s\\n' ${lib.escapeShellArg keySource.native.publicKey}"
      else if keySource.native.publicKeyFile != null then
        "cat ${lib.escapeShellArg (toString keySource.native.publicKeyFile)}"
      else
        ""
    else
      "";

  # Build a shell fragment that checks a single sops key. Binary secrets carry
  # the whole file, so no key extraction is possible there.
  keyCheck =
    {
      sops,
      file,
      fileShell ? null,
      key,
      format ? null,
    }:
    let
      fileArg = if fileShell == null then lib.escapeShellArg file else fileShell;
    in
    if format == "binary" then
      "${sops} --decrypt ${fileArg} >/dev/null"
    else
      let
        keyPath =
          "["
          + concatStringsSep "][" (
            map (part: "\"${part}\"") (lib.splitString "/" key)
          )
          + "]";
      in
      "${sops} --decrypt --extract ${lib.escapeShellArg keyPath} ${fileArg} >/dev/null";

in
{
  inherit
    clusterNameOf
    clusterRoot
    clusterRootCommand
    clusterSecretVisibleToMachine
    keepassEntry
    keepassExtractCommand
    keepassKeyFileArg
    keepassPasswordCommand
    keyCheck
    keySourceEnv
    keySourceOf
    keySourcePublicKeyCommand
    machineNameOf
    machineOf
    nodeByName
    resolveSopsFile
    resolveSopsFileCommand
    secretSopsFile
    secretSopsFileCommand
    selectedNodes
    serviceOf
    sopsRootOsPath
    sopsRootPath
    sopsRootSpec
    ;
}

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

  sopsRootPath = service: toString service.sopsRoot;

  # Helper commands use the documented <flakeRoot>/secrets convention. Keeping
  # this as a relative path means they work from the flake root without a
  # second writable-path option.
  sopsRootCommand = _service: "secrets";

  sopsConfigFile = _service: ".sops.yaml";

  clusterRootAt =
    root: clusterName:
    "${root}/${clusterName}";

  clusterRoot = service: clusterName: clusterRootAt (sopsRootPath service) clusterName;
  clusterRootCommand = service: clusterName: clusterRootAt (sopsRootCommand service) clusterName;

  machineSopsFileAt =
    root: service: clusterName: machineName:
    "${clusterRootAt root clusterName}/${service.machinesSubDir}/${machineName}.yaml";

  clusterSopsFileAt =
    root: service: clusterName:
    if service.clusterSopsFile != null then
      toString service.clusterSopsFile
    else
      "${clusterRootAt root clusterName}/cluster.yaml";

  groupSopsFileAt =
    root: service: clusterName: group:
    "${clusterRootAt root clusterName}/${service.clusterSubDir}/${group}.yaml";

  resolveSopsFileAt =
    {
      root,
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
      clusterSopsFileAt root service clusterName
    else if isString selected && hasPrefix "cluster/" selected then
      let
        group = removePrefix "cluster/" selected;
      in
      if group == "" || lib.hasInfix "/" group then
        throw "secret-service: invalid group sopsFile '${selected}'"
      else
        groupSopsFileAt root service clusterName group
    else if isPath selected then
      toString selected
    else if isString selected then
      selected
    else
      throw "secret-service: unsupported sopsFile value '${toString selected}'";

  resolveSopsFile =
    args:
    resolveSopsFileAt (
      args
      // {
        root = sopsRootPath args.service;
      }
    );

  resolveSopsFileCommand =
    args:
    resolveSopsFileAt (
      args
      // {
        root = sopsRootCommand args.service;
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
        key = head keySource.ssh.keyPaths;
      in
      "export SOPS_AGE_SSH_PRIVATE_KEY_FILE=${lib.escapeShellArg (toString key)}"
    else
      "";

  keySourcePublicKeyCommand =
    keySource:
    if keySource == null then
      ""
    else if keySource.type == "age" then
      "${ageKeygen} -y ${lib.escapeShellArg (toString keySource.age.sourceKeyFile)}"
    else if keySource.type == "keepass" then
      ''
        __secret_service_key="$(mktemp)"
        ${keepassExtractCommand keySource.keepass} > "$__secret_service_key"
        ${ageKeygen} -y "$__secret_service_key"
        rm -f "$__secret_service_key"
      ''
    else if keySource.type == "ssh" then
      let
        key = head keySource.ssh.keyPaths;
      in
      "${sshKeygen} -y -f ${lib.escapeShellArg (toString key)} | ${sshToAge}"
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
      key,
      format ? null,
    }:
    if format == "binary" then
      "${sops} --decrypt ${lib.escapeShellArg file} >/dev/null"
    else
      let
        keyPath =
          "["
          + concatStringsSep "][" (
            map (part: "\"${part}\"") (lib.splitString "/" key)
          )
          + "]";
      in
      "${sops} --decrypt --extract ${lib.escapeShellArg keyPath} ${lib.escapeShellArg file} >/dev/null";

in
{
  inherit
    clusterNameOf
    clusterRoot
    clusterRootCommand
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
    sopsConfigFile
    sopsRootCommand
    sopsRootPath
    ;
}

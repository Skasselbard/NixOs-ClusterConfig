# This file can be sourced by nushell to make command completions for the clusterConfig available

def completerFn [context:list<string> ] {
  if ($context | first) != "clusterConfig" {return []}

  let path = ($context | skip 1 | drop 1)
  # let path = ($context ++ "end"| split row ' ' | skip 1 | drop 1)
  let packages = $env.packageInfo | from json

  # return [( $path | str join '.') ]
  
  let packagTargetPath = $packages | get ( $path | into cell-path )

  if ($packagTargetPath | describe | str starts-with "record") {
    $packagTargetPath | columns
  } else {
    []
  }
  }

$env.config.completions.external = {
    enable: true
    max_results: 100
    completer: {|cmd| completerFn $cmd}
}

def subCommands [] {
    [
        { value: "info", description: "print information on the configuration of the cluster" },
        { value: "cluster", description: "run cluster level scripts from the generated flake packages" }
        { value: "machines", description: "run machine level scripts from the generated flake packages:" } 
        # TODO: other scripts
        # { value: "services", description: "run service level scripts from the generated flake packages" }
        # { value: "vms", description: "run virtual machine level scripts from the generated flake packages" }
        # { value: "logs", description: "get information from running machines" }
    ]
  }

def clusterConfig [subcommand: string@subCommands ...rest] {
  let path = ($subcommand ++ $rest) | str join '.'
  ^nix run $".#($path)"
}
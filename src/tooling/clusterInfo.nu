def "clusterConfig info" [
  --json # print the output as json
  ] {
  let result = ^nix eval $".#clusterInfo" --json  
  if $json {
    $result
  } else {
     $result | from json
  }

}

def "clusterConfig info packages" [
  --json # print the output as json
  ] {
  let result = ^nix eval $".#packageInfo" --json  
  if $json {
    $result
  } else {
     $result | from json
  }

}

def "main" [] {
  clusterConfig info --json
}

def "main packages" [] {
  clusterConfig info packages --json
}
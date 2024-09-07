{ pkgs, ... }:
let lib = pkgs.lib;
in {
  _class = "homeManager";

  programs = {

    # Handle bash with homeManager.
    # Otherwise the init script is not executed
    bash = { enable = true; };

    starship = {
      enable = true;
      enableBashIntegration = true;
      package = pkgs.starship;
      settings = let
        # colors
        neutral = "#090c0c";
        os = "#a3aed2";
        dir = "#769ff0";
        git = "#394260";
        fill = "";
        location = "";
        status = "#566aad";
        package = "#212736";
        time = "#1d2230";
        # modules
        packages = [
          "singularity"
          "kubernetes"
          "vcsh"
          "fossil_branch"
          "hg_branch"
          "pijul_channel"
          # "package"
          "c"
          "cmake"
          "cobol"
          "daml"
          "dart"
          "deno"
          "dotnet"
          "elixir"
          "elm"
          "erlang"
          "fennel"
          "golang"
          "guix_shell"
          "haskell"
          "haxe"
          "helm"
          "java"
          "julia"
          "kotlin"
          "gradle"
          "lua"
          "nim"
          "nodejs"
          "ocaml"
          "opa"
          "perl"
          "php"
          "pulumi"
          "purescript"
          "python"
          "raku"
          "rlang"
          "red"
          "ruby"
          "rust"
          "scala"
          "solidity"
          "swift"
          "terraform"
          "vlang"
          "vagrant"
          "zig"
          "buf"
          "nix_shell"
          "conda"
          "meson"
          "spack"
          "aws"
          "gcloud"
          "openstack"
          "azure"
          "crystal"
        ];
      in with builtins;
      lib.attrsets.recursiveUpdate
      # uniform style for package modules
      (listToAttrs (map (elem: {
        name = elem;
        value = {
          style = "bg:${package}";
          format = "[[ $symbol ($version) ](fg:${dir} bg:${package})]($style)";
        };
      }) packages))
      # all other style
      {
        format = builtins.concatStringsSep "" (lib.lists.flatten [
          "[](fg:${os})"
          "$os"
          "[](bg:${dir} fg:${os})"
          "$directory"
          "[](fg:${dir} bg:${git})"
          "$git_branch"
          "$git_status"
          "[](fg:${git})"
          "$sudo"
          "$username"
          "$fill"
          "$container"
          "$docker_context"
          "$hostname"
          "[](fg:${status})"
          "$status"
          "$cmd_duration"
          "$shell"
          "[](fg:${package} bg:${status})"
          (map (elem: "$" + elem) packages) # all packeges
          "[](bg:${package} fg:${time})"
          "$time"
          "[ ](fg:${time})"
          ''

            $character
          ''
        ]);
        continuation_prompt = "▶▶ ";
        os = {
          disabled = false;
          style = "bg:${os} fg:${neutral}";
        };
        username = {
          show_always = true;
          # style_user = "bg:#9A348E";
          # style_root = "bg:#9A348E";
          format = "[$user ]($style)";
          disabled = false;
        };
        hostname = {
          ssh_only = false;
          format = "[$ssh_symbol$hostname]($style) ";
        };
        sudo = {
          disabled = false;
          symbol = " 󰀋 "; # 󱢽 󰭐 󱥠 󰀋
          style = "bold red";
          format = "[$symbol]($style)";
        };
        directory = {
          style = "fg:#e3e5e5 bg:${dir}";
          format = "[ $path ]($style)";
          truncation_length = 3;
          truncation_symbol = "󰘍 "; # "󰶻 ⋙  ";
        };
        directory.substitutions = {
          "Documents" = "󰈙 ";
          "Downloads" = " ";
          "Music" = " ";
          "Pictures" = " ";
        };
        git_branch = {
          style = "bg:${git}";
          format = "[[ $symbol $branch ](fg:${dir} bg:${git})]($style)";
        };
        git_status = {
          style = "bg:${git}";
          format =
            "[[($all_status$ahead_behind )](fg:${dir} bg:${git})]($style)";
        };
        time = {
          disabled = false;
          time_format = "%R"; # Hour:Minute Format
          style = "bg:${time}";
          format = "[[  $time ](fg:#a0a9cb bg:${time})]($style)";
        };
        cmd_duration = {
          min_time = 500;
          style = "bg:${status}";
          format = "[$duration]($style)";
        };
        status.style = "bg:${status}";
        shell = {
          disabled = false;
          style = "bg:${status}";
          format = "[ $indicator]($style)";
        };
        # nerdfonts
        aws = { symbol = "  "; };
        buf = { symbol = " "; };
        c = { symbol = " "; };
        conda = { symbol = " "; };
        dart = { symbol = " "; };
        directory = { read_only = " 󰌾"; };
        docker_context = { symbol = " "; };
        elixir = { symbol = " "; };
        elm = { symbol = " "; };
        fossil_branch = { symbol = " "; };
        git_branch = { symbol = " "; };
        golang = { symbol = " "; };
        guix_shell = { symbol = " "; };
        haskell = { symbol = " "; };
        haxe = { symbol = " "; };
        hg_branch = { symbol = " "; };
        hostname = { ssh_symbol = " "; };
        java = { symbol = " "; };
        julia = { symbol = " "; };
        lua = { symbol = " "; };
        memory_usage = { symbol = "󰍛 "; };
        meson = { symbol = "󰔷 "; };
        nim = { symbol = "󰆥 "; };
        nix_shell = { symbol = " "; };
        nodejs = { symbol = " "; };
        os.symbols = {
          Alpaquita = " ";
          Alpine = " ";
          Amazon = " ";
          Android = " ";
          Arch = " ";
          Artix = " ";
          CentOS = " ";
          Debian = " ";
          DragonFly = " ";
          Emscripten = " ";
          EndeavourOS = " ";
          Fedora = " ";
          FreeBSD = " ";
          Garuda = "󰛓 ";
          Gentoo = " ";
          HardenedBSD = "󰞌 ";
          Illumos = "󰈸 ";
          Linux = " ";
          Mabox = " ";
          Macos = " ";
          Manjaro = " ";
          Mariner = " ";
          MidnightBSD = " ";
          Mint = " ";
          NetBSD = " ";
          NixOS = " ";
          OpenBSD = "󰈺 ";
          openSUSE = " ";
          OracleLinux = "󰌷 ";
          Pop = " ";
          Raspbian = " ";
          Redhat = " ";
          RedHatEnterprise = " ";
          Redox = "󰀘 ";
          Solus = "󰠳 ";
          SUSE = " ";
          Ubuntu = " ";
          Unknown = " ";
          Windows = "󰍲 ";
        };
        package = { symbol = "󰏗 "; };
        pijul_channel = { symbol = " "; };
        python = { symbol = " "; };
        rlang = { symbol = "󰟔 "; };
        ruby = { symbol = " "; };
        rust = { symbol = " "; };
        scala = { symbol = " "; };
      };
    };
  };
}

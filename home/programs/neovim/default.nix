{ config, lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    neovim
    xxd
  ];

  home.file = {
    ".config/nvim" = {
      source = ./nvim;
      recursive = true;
    };

    ".local/share/nvim/nix/alpha" = { source = "${pkgs.vimPlugins.alpha-nvim}"; recursive = true; };
    ".local/share/nvim/nix/b64" = { source = "${pkgs.vimPlugins.b64-nvim}"; recursive = true; };
    ".local/share/nvim/nix/cmp" = { source = "${pkgs.vimPlugins.nvim-cmp}"; recursive = true; };
    ".local/share/nvim/nix/cmp-buffer" = { source = "${pkgs.vimPlugins.cmp-buffer}"; recursive = true; };
    ".local/share/nvim/nix/cmp-cmdline" = { source = "${pkgs.vimPlugins.cmp-cmdline}"; recursive = true; };
    ".local/share/nvim/nix/cmp-fzy-buffer" = { source = "${pkgs.vimPlugins.cmp-fuzzy-buffer}"; recursive = true; };
    ".local/share/nvim/nix/cmp-nvim-lsp" = { source = "${pkgs.vimPlugins.cmp-nvim-lsp}"; recursive = true; };
    ".local/share/nvim/nix/cmp-nvim-lsp-document-symbol" = { source = "${pkgs.vimPlugins.cmp-nvim-lsp-document-symbol}"; recursive = true; };
    ".local/share/nvim/nix/cmp-nvim-lsp-signature-help" = { source = "${pkgs.vimPlugins.cmp-nvim-lsp-signature-help}"; recursive = true; };
    ".local/share/nvim/nix/cmp-nvim-lua" = { source = "${pkgs.vimPlugins.cmp-nvim-lua}"; recursive = true; };
    ".local/share/nvim/nix/cmp-pandoc" = { source = "${pkgs.vimPlugins.cmp-pandoc-nvim}"; recursive = true; };
    ".local/share/nvim/nix/cmp-path" = { source = "${pkgs.vimPlugins.cmp-path}"; recursive = true; };
    ".local/share/nvim/nix/cmp-spell" = { source = "${pkgs.vimPlugins.cmp-spell}"; recursive = true; };
    ".local/share/nvim/nix/cmp-tmux" = { source = "${pkgs.vimPlugins.cmp-tmux}"; recursive = true; };
    ".local/share/nvim/nix/colorizer" = { source = "${pkgs.vimPlugins.nvim-colorizer-lua}"; recursive = true; };
    ".local/share/nvim/nix/comment-nvim" = { source = "${pkgs.vimPlugins.comment-nvim}"; recursive = true; };
    ".local/share/nvim/nix/committia" = { source = "${pkgs.vimPlugins.committia-vim}"; recursive = true; };
    ".local/share/nvim/nix/copilot-cmp" = { source = "${pkgs.vimPlugins.copilot-cmp}"; recursive = true; };
    ".local/share/nvim/nix/copilot-lua" = { source = "${pkgs.vimPlugins.copilot-lua}"; recursive = true; };
    ".local/share/nvim/nix/crates" = { source = "${pkgs.vimPlugins.crates-nvim}"; recursive = true; };
    ".local/share/nvim/nix/dap" = { source = "${pkgs.vimPlugins.nvim-dap}"; recursive = true; };
    ".local/share/nvim/nix/direnv" = { source = "${pkgs.vimPlugins.direnv-vim}"; recursive = true; };
    ".local/share/nvim/nix/easy-align" = { source = "${pkgs.vimPlugins.vim-easy-align}"; recursive = true; };
    ".local/share/nvim/nix/everforest" = { source = "${pkgs.vimPlugins.everforest}"; recursive = true; };
    ".local/share/nvim/nix/fidget" = { source = "${pkgs.vimPlugins.fidget-nvim}"; recursive = true; };
    ".local/share/nvim/nix/fixcursorhold" = { source = "${pkgs.vimPlugins.FixCursorHold-nvim}"; recursive = true; };
    ".local/share/nvim/nix/fubitive" = { source = "${pkgs.vimPlugins.vim-fubitive}"; recursive = true; };
    ".local/share/nvim/nix/fugitive" = { source = "${pkgs.vimPlugins.vim-fugitive}"; recursive = true; };
    ".local/share/nvim/nix/fugitive-gitlab" = { source = "${pkgs.vimPlugins.fugitive-gitlab-vim}"; recursive = true; };
    ".local/share/nvim/nix/fuzzy-nvim" = { source = "${pkgs.vimPlugins.fuzzy-nvim}"; recursive = true; };
    ".local/share/nvim/nix/fzf" = { source = "${pkgs.vimPlugins.fzfWrapper}"; recursive = true; };
    ".local/share/nvim/nix/ufo" = { source = "${pkgs.vimPlugins.nvim-ufo}"; recursive = true; };
    ".local/share/nvim/nix/fzy-lua-native" = { source = "${pkgs.vimPlugins.telescope-fzy-native-nvim}"; recursive = true; };
    ".local/share/nvim/nix/gina" = { source = "${pkgs.vimPlugins.gina-vim}"; recursive = true; };
    ".local/share/nvim/nix/promise-async" = { source = "${pkgs.vimPlugins.promise-async}"; recursive = true; };
    ".local/share/nvim/nix/gist" = { source = "${pkgs.vimPlugins.vim-gist}"; recursive = true; };
    ".local/share/nvim/nix/git-messenger" = { source = "${pkgs.vimPlugins.git-messenger-vim}"; recursive = true; };
    ".local/share/nvim/nix/luasnip" = { source = "${pkgs.vimPlugins.luasnip}"; recursive = true; };
    ".local/share/nvim/nix/git-worktree" = { source = "${pkgs.vimPlugins.git-worktree-nvim}"; recursive = true; };
    ".local/share/nvim/nix/mason-lspconfig" = { source = "${pkgs.vimPlugins.mason-lspconfig-nvim}"; recursive = true; };
    ".local/share/nvim/nix/rust-tools" = { source = "${pkgs.vimPlugins.rust-tools-nvim}"; recursive = true; };
    ".local/share/nvim/nix/gitsigns" = { source = "${pkgs.vimPlugins.gitsigns-nvim}"; recursive = true; };
    ".local/share/nvim/nix/grammarous" = { source = "${pkgs.vimPlugins.vim-grammarous}"; recursive = true; };
    ".local/share/nvim/nix/harpoon" = { source = "${pkgs.vimPlugins.harpoon}"; recursive = true; };
    ".local/share/nvim/nix/helm" = { source = "${pkgs.vimPlugins.vim-helm}"; recursive = true; };
    ".local/share/nvim/nix/illuminate" = { source = "${pkgs.vimPlugins.vim-illuminate}"; recursive = true; };
    ".local/share/nvim/nix/indent-blankline" = { source = "${pkgs.vimPlugins.plenary-nvim}"; recursive = true; };
    ".local/share/nvim/nix/jdtls" = { source = "${pkgs.vimPlugins.nvim-jdtls}"; recursive = true; };
    ".local/share/nvim/nix/kanagawa" = { source = "${pkgs.vimPlugins.kanagawa-nvim}"; recursive = true; };
    ".local/share/nvim/nix/lastplace" = { source = "${pkgs.vimPlugins.nvim-lastplace}"; recursive = true; };
    ".local/share/nvim/nix/lazy" = { source = "${pkgs.vimPlugins.lazy-nvim}"; recursive = true; };
    ".local/share/nvim/nix/lsp-inlayhints" = { source = "${pkgs.vimPlugins.alpha-nvim}"; recursive = true; };
    ".local/share/nvim/nix/lspconfig" = { source = "${pkgs.vimPlugins.nvim-lspconfig}"; recursive = true; };
    ".local/share/nvim/nix/mason" = { source = "${pkgs.vimPlugins.mason-nvim}"; recursive = true; };
    ".local/share/nvim/nix/neotest" = { source = "${pkgs.vimPlugins.neotest}"; recursive = true; };
    ".local/share/nvim/nix/neotest-go" = { source = "${pkgs.vimPlugins.neotest-go}"; recursive = true; };
    ".local/share/nvim/nix/neotest-python" = { source = "${pkgs.vimPlugins.neotest-python}"; recursive = true; };
    ".local/share/nvim/nix/neotest-rust" = { source = "${pkgs.vimPlugins.neotest-rust}"; recursive = true; };
    ".local/share/nvim/nix/nvim-treesitter-context" = { source = "${pkgs.vimPlugins.nvim-treesitter-context}"; recursive = true; };
    ".local/share/nvim/nix/nvim-web-devicons" = { source = "${pkgs.vimPlugins.nvim-web-devicons}"; recursive = true; };
    ".local/share/nvim/nix/plenary" = { source = "${pkgs.vimPlugins.plenary-nvim}"; recursive = true; };
    ".local/share/nvim/nix/popup" = { source = "${pkgs.vimPlugins.popup-nvim}"; recursive = true; };
    ".local/share/nvim/nix/project-nvim" = { source = "${pkgs.vimPlugins.project-nvim}"; recursive = true; };
    ".local/share/nvim/nix/ray-x-go" = { source = "${pkgs.vimPlugins.go-nvim}"; recursive = true; };
    ".local/share/nvim/nix/repeat" = { source = "${pkgs.vimPlugins.vim-repeat}"; recursive = true; };
    ".local/share/nvim/nix/split-navigator" = { source = "${pkgs.vimPlugins.Navigator-nvim}"; recursive = true; };
    ".local/share/nvim/nix/telescope" = { source = "${pkgs.vimPlugins.telescope-nvim}"; recursive = true; };
    ".local/share/nvim/nix/telescope-dap" = { source = "${pkgs.vimPlugins.telescope-dap-nvim}"; recursive = true; };
    ".local/share/nvim/nix/telescope-file-browser" = { source = "${pkgs.vimPlugins.telescope-file-browser-nvim}"; recursive = true; };
    ".local/share/nvim/nix/telescope-fzy-native" = { source = "${pkgs.vimPlugins.telescope-fzy-native-nvim}"; recursive = true; };
    ".local/share/nvim/nix/telescope-github" = { source = "${pkgs.vimPlugins.telescope-github-nvim}"; recursive = true; };
    ".local/share/nvim/nix/telescope-ui-select" = { source = "${pkgs.vimPlugins.telescope-ui-select-nvim}"; recursive = true; };
    ".local/share/nvim/nix/telescope-zoxide" = { source = "${pkgs.vimPlugins.telescope-zoxide}"; recursive = true; };
    ".local/share/nvim/nix/terraform" = { source = "${pkgs.vimPlugins.vim-terraform}"; recursive = true; };
    ".local/share/nvim/nix/terraform-completion" = { source = "${pkgs.vimPlugins.vim-terraform-completion}"; recursive = true; };
    ".local/share/nvim/nix/todo-comments" = { source = "${pkgs.vimPlugins.todo-comments-nvim}"; recursive = true; };
    ".local/share/nvim/nix/tokyonight" = { source = "${pkgs.vimPlugins.tokyonight-nvim}"; recursive = true; };
    ".local/share/nvim/nix/treesitter" = { source = "${pkgs.vimPlugins.nvim-treesitter}"; recursive = true; };
    ".local/share/nvim/nix/treesitter-textobjects" = { source = "${pkgs.vimPlugins.nvim-treesitter-textobjects}"; recursive = true; };
    ".local/share/nvim/nix/trouble" = { source = "${pkgs.vimPlugins.trouble-nvim}"; recursive = true; };
    ".local/share/nvim/nix/twilight" = { source = "${pkgs.vimPlugins.twilight-nvim}"; recursive = true; };
    ".local/share/nvim/nix/typescript" = { source = "${pkgs.vimPlugins.typescript-nvim}"; recursive = true; };
    ".local/share/nvim/nix/unimpaired" = { source = "${pkgs.vimPlugins.vim-terraform-completion}"; recursive = true; };
    ".local/share/nvim/nix/vim-rhubarb" = { source = "${pkgs.vimPlugins.vim-rhubarb}"; recursive = true; };
    ".local/share/nvim/nix/webapi" = { source = "${pkgs.vimPlugins.vim-gist}"; recursive = true; };
    ".local/share/nvim/nix/which-key" = { source = "${pkgs.vimPlugins.which-key-nvim}"; recursive = true; };
    ".local/share/nvim/nix/zen-mode" = { source = "${pkgs.vimPlugins.zen-mode-nvim}"; recursive = true; };

    ".local/share/nvim/nix/bacon" = {
      source = pkgs.fetchFromGitHub {
        owner = "Canop";
        repo = "bacon";
        rev = "33d7625a38d7437ec116fb70c03c8cee68cfae7b";
        sha256 = "nuWqMWiwhvnqCZJJuvIK+DZ1NocRMJlkiDTHWb2EKFo=";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/deadcolumn" = {
      source = pkgs.fetchFromGitHub {
        owner = "Bekaboo";
        repo = "deadcolumn.nvim";
        rev = "b9b5e237371ae5379e280e4df9ecf62e4bc8d7a5";
        sha256 = "vUSCkWiaHxdpV6RNF0YHUvf9PCw+SLr/O9AlsaQH3hU=";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/devdocs" = {
      source = pkgs.fetchFromGitHub {
        owner = "luckasRanarison";
        repo = "nvim-devdocs";
        rev = "6685d79107627f6d7edcd4a6bf851c459066bdf4";
        sha256 = "befzyGE0JhA+tBC46DDBPFX73wv/HKOPjLGO0LWedbY=";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/conform" = {
      source = pkgs.fetchFromGitHub {
        owner = "stevearc";
        repo = "conform.nvim";
        rev = "a36c68d2cd551e49883ddb2492c178d915567f58";
        sha256 = "aul/6sQZMljF3nc+WrRhVEObytu4wkoVyTM5HognK7E=";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/guihua" = {
      source = pkgs.fetchFromGitHub {
        owner = "ray-x";
        repo = "guihua.lua";
        rev = "cd68996069abedffcd677ca7eee3a660b79e5b32";
        sha256 = "2eXvIqPJP76kJwnLtgTLCsti0R0Kzpp1w7ov2xZc2D0=";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/trailblazer" = {
      source = pkgs.fetchFromGitHub {
        owner = "LeonHeidelbach";
        repo = "trailblazer.nvim";
        rev = "674bb6254a376a234d0d243366224122fc064eab";
        sha256 = "9q8CmbUGmbKb7w4fzOS7XBSg8YM5WwqwvLUN2pVOAtI=";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/hlargs" = {
      source = pkgs.fetchFromGitHub {
        owner = "m-demare";
        repo = "hlargs.nvim";
        rev = "6218a401824c5733ac50b264991b62d064e85ab2";
        sha256 = "bH0OOf5T4Z96Td4ZBV1q8DI/bO1pV8DwqEWho6jeggg=";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/lsp-zero" = {
      source = pkgs.fetchFromGitHub {
        owner = "VonHeikemen";
        repo = "lsp-zero.nvim";
        rev = "8a9ee4e11a3e23101d1d1d11aaac3159ad925cc9";
        sha256 = "oXKKVf+QeHAiiJ1ft0D+o80ikc6VxBlBHb+VKrRK02o=";
      };
    };
    ".local/share/nvim/nix/navigator" = {
      source = pkgs.fetchFromGitHub {
        owner = "ray-x";
        repo = "navigator.lua";
        rev = "3e05ae2b6caa74565cc7f4116fe0eff443f0fa50";
        sha256 = "b5VsV6G8Rcu3pT66WelXKSQaVamGmn6897fBqbMf92s=";
      };
    };
  };
}

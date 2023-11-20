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

    ".local/share/nvim/nix/alpha" = {
      source = pkgs.fetchFromGitHub {
        owner = "goolord";
        repo = "alpha-nvim";
        rev = "234822140b265ec4ba3203e3e0be0e0bb826dff5";
        sha256 = "15iq6wkcij0sxngs3y221nffk3rk215frifklxzc2db5s9na4w5d";
      };
    };
    ".local/share/nvim/nix/b64" = {
      source = pkgs.fetchFromGitHub {
        owner = "taybart";
        repo = "b64.nvim";
        rev = "0efc9f2d5baf546298c3ef936434fe5783d7ecb3";
        sha256 = "1sb24ydihp01qkrvfr1pc2wf5yjl9sb8b893x5hm6l8q8a70pr5h";
      };
    };
    ".local/share/nvim/nix/cmp" = {
      source = pkgs.fetchFromGitHub {
        owner = "hrsh7th";
        repo = "nvim-cmp";
        rev = "0b751f6beef40fd47375eaf53d3057e0bfa317e4";
        sha256 = "1qp7s2iam9zzdlw5sgkk6c623z7vjgga0rcg63ja0f836l90grba";
      };
    };
    ".local/share/nvim/nix/cmp-buffer" = {
      source = pkgs.fetchFromGitHub {
        owner = "hrsh7th";
        repo = "cmp-buffer";
        rev = "3022dbc9166796b644a841a02de8dd1cc1d311fa";
        sha256 = "1cwx8ky74633y0bmqmvq1lqzmphadnhzmhzkddl3hpb7rgn18vkl";
      };
    };
    ".local/share/nvim/nix/cmp-cmdline" = {
      source = pkgs.fetchFromGitHub {
        owner = "hrsh7th";
        repo = "cmp-cmdline";
        rev = "8ee981b4a91f536f52add291594e89fb6645e451";
        sha256 = "03j79ncxnnpilx17x70my7s8vvc4w81kipraq29g4vp32dggzjsv";
      };
    };
    ".local/share/nvim/nix/cmp-fzy-buffer" = {
      source = pkgs.fetchFromGitHub {
        owner = "tzachar";
        repo = "cmp-fuzzy-buffer";
        rev = "ada6352bc7e3c32471ab6c08f954001870329de1";
        sha256 = "0qhzjhcdfwykswd4zxpmgmsiy18vmmdskidakjjwmfhfxp225hpi";
      };
    };
    ".local/share/nvim/nix/cmp-nvim-lsp" = {
      source = pkgs.fetchFromGitHub {
        owner = "hrsh7th";
        repo = "cmp-nvim-lsp";
        rev = "44b16d11215dce86f253ce0c30949813c0a90765";
        sha256 = "1ny64ls3z9pcflsg3sd7xnd795mcfbqhyan3bk4ymxgv5jh2qkcr";
      };
    };
    ".local/share/nvim/nix/cmp-nvim-lsp-document-symbol" = {
      source = pkgs.fetchFromGitHub {
        owner = "hrsh7th";
        repo = "cmp-nvim-lsp-document-symbol";
        rev = "f0f53f704c08ea501f9d222b23491b0d354644b0";
        sha256 = "1zcplbb2kkq3f9mmy6zfgscdiccqiwkjr4d91qqjxp80yi1v9z4j";
      };
    };

    ".local/share/nvim/nix/cmp-nvim-lsp-signature-help" = {
      source = pkgs.fetchFromGitHub {
        owner = "hrsh7th";
        repo = "cmp-nvim-lsp-signature-help";
        rev = "3d8912ebeb56e5ae08ef0906e3a54de1c66b92f1";
        sha256 = "0bkviamzpkw6yv4cyqa9pqm1g2gsvzk87v8xc4574yf86jz5hg68";
      };
    };
    ".local/share/nvim/nix/cmp-nvim-lua" = {
      source = pkgs.fetchFromGitHub {
        owner = "hrsh7th";
        repo = "cmp-nvim-lua";
        rev = "f12408bdb54c39c23e67cab726264c10db33ada8";
        sha256 = "18qqcqjyxrmzvpj7m7wyjx1313h66vg8992n6y9lwawmb4mwxrg9";
      };
    };
    ".local/share/nvim/nix/cmp-pandoc" = {
      source = pkgs.fetchFromGitHub {
        owner = "aspeddro";
        repo = "cmp-pandoc.nvim";
        rev = "30faa4456a7643c4cb02d8fa18438fd484ed7602";
        sha256 = "0fl903hcy85f21xmgf1dx31lxjwgplkcg4m8i989yhqr6irwwi6f";
      };
    };
    ".local/share/nvim/nix/cmp-path" = {
      source = pkgs.fetchFromGitHub {
        owner = "hrsh7th";
        repo = "cmp-path";
        rev = "91ff86cd9c29299a64f968ebb45846c485725f23";
        sha256 = "18ixx14ibc7qrv32nj0ylxrx8w4ggg49l5vhcqd35hkp4n56j6mn";
      };
    };

    ".local/share/nvim/nix/cmp-spell" = {
      source = pkgs.fetchFromGitHub {
        owner = "f3fora";
        repo = "cmp-spell";
        rev = "32a0867efa59b43edbb2db67b0871cfad90c9b66";
        sha256 = "1yr2cq1b6di4k93pjlshkkf4phhd3lzmkm0s679j35crzgwhxnbd";
      };
    };
    ".local/share/nvim/nix/cmp-tmux" = {
      source = pkgs.fetchFromGitHub {
        owner = "andersevenrud";
        repo = "cmp-tmux";
        rev = "97ec06b8030b8bf6d1fd83d49bdd16c98e04c845";
        sha256 = "0a9yryb1hwmkv3gmahx3barclllgbqhfp7q00i5zrc69ql0i63vf";
      };
    };

    ".local/share/nvim/nix/colorizer" = {
      source = pkgs.fetchFromGitHub {
        owner = "norcalli";
        repo = "nvim-colorizer.lua";
        rev = "36c610a9717cc9ec426a07c8e6bf3b3abcb139d6";
        sha256 = "0gvqdfkqf6k9q46r0vcc3nqa6w45gsvp8j4kya1bvi24vhifg2p9";
      };
    };
    ".local/share/nvim/nix/comment-nvim" = {
      source = pkgs.fetchFromGitHub {
        owner = "numToStr";
        repo = "Comment.nvim";
        rev = "0236521ea582747b58869cb72f70ccfa967d2e89";
        sha256 = "1mvi7c6n9ybgs6lfylzhkidifa6jkgsbj808knx57blvi5k7blgr";
      };
    };

    ".local/share/nvim/nix/committia" = {
      source = pkgs.fetchFromGitHub {
        owner = "rhysd";
        repo = "committia.vim";
        rev = "0b4df1a7f48ffbc23b009bd14d58ee1be541917c";
        sha256 = "1scz52n6y2qrqd74kcsgvjkmxd37wmgzx2wail4sz88h3cks8w39";
      };
    };
    ".local/share/nvim/nix/copilot-cmp" = {
      source = pkgs.fetchFromGitHub {
        owner = "zbirenbaum";
        repo = "copilot-cmp";
        rev = "72fbaa03695779f8349be3ac54fa8bd77eed3ee3";
        sha256 = "09j6jm77dw6g0d2yxxg954kbsf7vx4zgjyfjq1n9ls5z36i0vf5j";
      };
    };
    ".local/share/nvim/nix/copilot-lua" = {
      source = pkgs.fetchFromGitHub {
        owner = "zbirenbaum";
        repo = "copilot.lua";
        rev = "73047082d72fcfdde1f73b7f17ad495cffcbafaa";
        sha256 = "159ghjskc2gydxvxsiijgz4swgad0njkmppalkj685wv5kl46pyg";
      };
    };
    ".local/share/nvim/nix/crates" = {
      source = pkgs.fetchFromGitHub {
        owner = "Saecki";
        repo = "crates.nvim";
        rev = "406295abeb7eedae3bcee3f0db690ada605c629c";
        sha256 = "1kiw5vkx3kqd5niyjnpimihd0cb5w8fz8pyq6sfh5am7ycvg5nfj";
      };
    };

    ".local/share/nvim/nix/dap" = {
      source = pkgs.fetchFromGitHub {
        owner = "mfussenegger";
        repo = "nvim-dap";
        rev = "e154fdb6d70b3765d71f296e718b29d8b7026a63";
        sha256 = "156hp1i8vm0fpy5vbcx0ihazblnly72vjsiy8bf9f30i9rvq9knv";
      };
    };

    ".local/share/nvim/nix/direnv" = {
      source = pkgs.fetchFromGitHub {
        owner = "direnv";
        repo = "direnv";
        rev = "9f22a3ea7e9fc835bb0569f14b35d756d02a4b7c";
        sha256 = "1vqiw951h01592gfcyjzysj7gpz5af8al4a1rk7mp76md55ddgnm";
      };
    };

    ".local/share/nvim/nix/easy-align" = {
      source = pkgs.fetchFromGitHub {
        owner = "junegunn";
        repo = "vim-easy-align";
        rev = "12dd6316974f71ce333e360c0260b4e1f81169c3";
        sha256 = "BpjYYAfpUCLitNfRsRnfzxsOIHA6T/WmL05BjRRt7j4=";
      };
    };

    ".local/share/nvim/nix/everforest" = {
      source = pkgs.fetchFromGitHub {
        owner = "neanias";
        repo = "everforest-nvim";
        rev = "6e06de0a08afc09c7e63acc4ace8c748fe48d8b9";
        sha256 = "0d3pdj280lx52n7bjz2rvcic1irym8gzry703ki0rq338ahd40bk";
      };
    };

    ".local/share/nvim/nix/fidget" = {
      source = pkgs.fetchFromGitHub {
        owner = "j-hui";
        repo = "fidget.nvim";
        rev = "a1493d94ecb3464ab3ae4d5855765310566dace4";
        sha256 = "09hr2l3y0b4j3r308xqmj0pa8nqsx13x1g2ar3bpyj5dz42m8kgg";
      };
    };
    ".local/share/nvim/nix/fixcursorhold" = {
      source = pkgs.fetchFromGitHub {
        owner = "antoinemadec";
        repo = "FixCursorHold.nvim";
        rev = "1900f89dc17c603eec29960f57c00bd9ae696495";
        sha256 = "0p7xh31qp836xvxbm1y3r4djv3r7ivxhx7jxwzgd380d029ql1hz";
      };
    };
    ".local/share/nvim/nix/fubitive" = {
      source = pkgs.fetchFromGitHub {
        owner = "tommcdo";
        repo = "vim-fubitive";
        rev = "c85ca8fa2098aa05e816f5d0839a0dad6bfcca5a";
        sha256 = "1ri3wz4yqy0g56k9mz279a8hcmyhxk7bv4slpv1xsm3yr1zf24jp";
      };
    };

    ".local/share/nvim/nix/fugitive" = {
      source = pkgs.fetchFromGitHub {
        owner = "tpope";
        repo = "vim-fugitive";
        rev = "46eaf8918b347906789df296143117774e827616";
        sha256 = "b6x8suCHRMYzqu/PGlt5FPg+7/CilkjWzlkBZ3i3H/c=";
      };
    };

    ".local/share/nvim/nix/fugitive-gitlab" = {
      source = pkgs.fetchFromGitHub {
        owner = "shumphrey";
        repo = "fugitive-gitlab.vim";
        rev = "55fed481c0309b3405dd3d72921d687bf36873a8";
        sha256 = "0y1gkbnihinwi4psf1d5ldixnrpdskllzz3na06gdw0hl4ampq60";
      };
    };

    ".local/share/nvim/nix/fuzzy-nvim" = {
      source = pkgs.fetchFromGitHub {
        owner = "amirrezaask";
        repo = "fuzzy.nvim";
        rev = "0ed93b8e8c78ddbf4539a3bb464a60ce6ecaf6e6";
        sha256 = "1v4zs5sp79id7cv6nal4z2cci8wfm18mjnff8f0nwjfakihmimh4";
      };
    };

    ".local/share/nvim/nix/fzf" = {
      source = pkgs.fetchFromGitHub {
        owner = "junegunn";
        repo = "fzf";
        rev = "7c674ad7fa3bc2db59645030170cc6012f785d9d";
        sha256 = "02msm4h25p7nhn7jwy7wkps3aghl1vm7395d70acdzw3r59ivdpl";
      };
    };
    ".local/share/nvim/nix/ufo" = {
      source = pkgs.fetchFromGitHub {
        owner = "kevinhwang91";
        repo = "nvim-ufo";
        rev = "a6132d058f23d15686f07b8e1ca252e060a0e0ce";
        sha256 = "0ijlsw9x3g2h48wvcagp1h4pvyjrrlc1cn0jni5pqs6fqjlcbypk";
      };
    };

    ".local/share/nvim/nix/fzy-lua-native" = {
      source = pkgs.fetchFromGitHub {
        owner = "romgrk";
        repo = "fzy-lua-native";
        rev = "820f745b7c442176bcc243e8f38ef4b985febfaf";
        sha256 = "1zhrql0ym0l24jvdjbz6qsf6j896cklazgksssa384gfd8s33bi5";
      };
    };
    ".local/share/nvim/nix/gina" = {
      source = pkgs.fetchFromGitHub {
        owner = "lambdalisue";
        repo = "gina.vim";
        rev = "ff6c2ddeca98f886b57fb42283c12e167d6ab575";
        sha256 = "09jlnpix2dy6kggiz96mrm5l1f9x1gl5afpdmfrxgkighn2rwpzq";
      };
    };
    ".local/share/nvim/nix/promise-async" = {
      source = pkgs.fetchFromGitHub {
        owner = "kevinhwang91";
        repo = "promise-async";
        rev = "e94f35161b8c5d4a4ca3b6ff93dd073eb9214c0e";
        sha256 = "0cavxw5v3nhnrs26r7cqxirq2ydk5g1ymcd3m4gf4rjjw9n067sd";
      };
    };
    ".local/share/nvim/nix/gist" = {
      source = pkgs.fetchFromGitHub {
        owner = "rawnly";
        repo = "gist.nvim";
        rev = "92b13e486dd9fd083750450e0d262fcc68a62b91";
        sha256 = "0ghqgddixfcnyhimdi3zwqxg89a3llvjmim50bpa01a49kfzbkch";
      };
    };

    ".local/share/nvim/nix/git-messenger" = {
      source = pkgs.fetchFromGitHub {
        owner = "rhysd";
        repo = "git-messenger.vim";
        rev = "8a61bdfa351d4df9a9118ee1d3f45edbed617072";
        sha256 = "0p4pj11sxl3bb2dqsnxwrpn0pf76df1r98wwj9lhjvy7514wc2a8";
      };
    };
    ".local/share/nvim/nix/luasnip" = {
      source = pkgs.fetchFromGitHub {
        owner = "L3MON4D3";
        repo = "LuaSnip";
        rev = "cab667e2674881001a86a7478fff7dc7791c63f5";
        sha256 = "10ij1bd3rdbyc87rlnq89h59gxmz6kfpq4wqbdhy9cml996ixpkp";
      };
    };
    ".local/share/nvim/nix/git-worktree" = {
      source = pkgs.fetchFromGitHub {
        owner = "ThePrimeagen";
        repo = "git-worktree.nvim";
        rev = "f247308e68dab9f1133759b05d944569ad054546";
        sha256 = "0mspffvg2z5lx4ck96d2pnf1azy3s1zq720n6abnxzajadmnh47r";
      };
    };
    ".local/share/nvim/nix/rust-tools" = {
      source = pkgs.fetchFromGitHub {
        owner = "simrat39";
        repo = "rust-tools.nvim";
        rev = "0cc8adab23117783a0292a0c8a2fbed1005dc645";
        sha256 = "0643bwpsjqg36wqyvj7mlnlmasly7am4jjzaabkiqwlz307z5mwf";
      };
    };
    ".local/share/nvim/nix/gitsigns" = {
      source = pkgs.fetchFromGitHub {
        owner = "lewis6991";
        repo = "gitsigns.nvim";
        rev = "0ccd5fb2316b3f8d8b2f775bc31cae7bc6a77a55";
        sha256 = "0xgw0p6wb33wlb4lnnjj1adxsll6lnmq3niabqzricsz4phmvf4f";
      };
    };
    ".local/share/nvim/nix/grammarous" = {
      source = pkgs.fetchFromGitHub {
        owner = "rhysd";
        repo = "vim-grammarous";
        rev = "db46357465ce587d5325e816235b5e92415f8c05";
        sha256 = "014g5q3kdqq4w5jvp61h26n0jfq05xz82rhwgcp3bgq0ffhrch7j";
      };
    };
    ".local/share/nvim/nix/harpoon" = {
      source = pkgs.fetchFromGitHub {
        owner = "ThePrimeagen";
        repo = "harpoon";
        rev = "c1aebbad9e3d13f20bedb8f2ce8b3a94e39e424a";
        sha256 = "0wqxg31z7gi7ap8r0057lpadywx3d245ghlljr6mkmp0jz3waad5";
      };
    };
    ".local/share/nvim/nix/helm" = {
      source = pkgs.fetchFromGitHub {
        owner = "towolf";
        repo = "vim-helm";
        rev = "c2e7b85711d410e1d73e64eb5df7b70b1c4c10eb";
        sha256 = "1khisqaiq0gvjn2p3w42vcwadcbcs2ml5x6mi3gaclp7q0hyc19m";
      };
    };
    ".local/share/nvim/nix/illuminate" = {
      source = pkgs.fetchFromGitHub {
        owner = "RRethy";
        repo = "vim-illuminate";
        rev = "3bd2ab64b5d63b29e05691e624927e5ebbf0fb86";
        sha256 = "0x3li63dijw9z4imbajpxbrclw32649810bsnx5cawrqgbc7kl99";
      };
    };
    ".local/share/nvim/nix/indent-blankline" = {
      source = pkgs.fetchFromGitHub {
        owner = "lukas-reineke";
        repo = "indent-blankline.nvim";
        rev = "29be0919b91fb59eca9e90690d76014233392bef";
        sha256 = "0z8n9d6f4qiq8m4ai1r2xz90955cp6cikqprq74ivfch3icrzdi1";
      };
    };
    ".local/share/nvim/nix/jdtls" = {
      source = pkgs.fetchFromGitHub {
        owner = "mfussenegger";
        repo = "nvim-jdtls";
        rev = "503a399e0d0b5d432068ab5ae24b9848891b0d53";
        sha256 = "0qq8sr32k9wv92km71h5clpmhsnck3i0dj40qapabb3iaw8iwhwf";
      };
    };
    ".local/share/nvim/nix/kanagawa" = {
      source = pkgs.fetchFromGitHub {
        owner = "rebelot";
        repo = "kanagawa.nvim";
        rev = "c19b9023842697ec92caf72cd3599f7dd7be4456";
        sha256 = "07wwz1z3am862igx6hkkyymvj2807a1a0y51324jvk27csidrcm5";
      };
    };
    ".local/share/nvim/nix/lastplace" = {
      source = pkgs.fetchFromGitHub {
        owner = "pchuan98";
        repo = "nvim-lastplace";
        rev = "c8850451fbd66130e564fc8472b4d9b439d4f476";
        sha256 = "0cjzwcrh5qi5lpisbnznh7g7c5asc4pgqzkjiglgrmrcax2w1sgm";
      };
    };
    ".local/share/nvim/nix/lazy" = {
      source = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "lazy.nvim";
        rev = "96584866b9c5e998cbae300594d0ccfd0c464627";
        sha256 = "11s0ddi1zcnyrh1q73jp2a4whvpajiwjd6dv8igfwj4jr21mrl39";
      };
    };
    ".local/share/nvim/nix/lsp-inlayhints" = {
      source = pkgs.fetchFromGitHub {
        owner = "lvimuser";
        repo = "lsp-inlayhints.nvim";
        rev = "d981f65c9ae0b6062176f0accb9c151daeda6f16";
        sha256 = "1x1ri9gcavl2swwhi0vn5cknh2db4p5r274r70zfwc2yxhks586k";
      };
    };

    ".local/share/nvim/nix/lspconfig" = {
      source = pkgs.fetchFromGitHub {
        owner = "neovim";
        repo = "nvim-lspconfig";
        rev = "7fedba8b1f8d0080c775851c429b88fd2ed4c6f5";
        sha256 = "0l7lc35fixf7yhdr80f4b39rljyfvfj7alxl9kn6mc6qaffh8vg4";
      };
    };
    ".local/share/nvim/nix/neotest" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-neotest";
        repo = "neotest";
        rev = "d424d262d01bccc1e0b038c9a7220a755afd2a1f";
        sha256 = "1sg8m77hik1gffrqy4038sivhr8yhg536dp6yr5gbnbrjvc35dgm";
      };
    };
    ".local/share/nvim/nix/neotest-go" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-neotest";
        repo = "neotest-go";
        rev = "1a15e1136db43775214a3e7a598f8930c29c94b7";
        sha256 = "06j4d0ii46556hwx4ygjajr2mm2wdb3vgjrq4hldfjfb2033wnxg";
      };
    };
    ".local/share/nvim/nix/neotest-python" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-neotest";
        repo = "neotest-python";
        rev = "c969a5b0073f2b5c8eaf017d1652f9251d761a15";
        sha256 = "0vjbc6sj9d4l8553g10wqxqpjr8z064g143i4ig4d42vsxh24ccc";
      };
    };
    ".local/share/nvim/nix/neotest-rust" = {
      source = pkgs.fetchFromGitHub {
        owner = "rouge8";
        repo = "neotest-rust";
        rev = "09394f787e64e2ab5f429c01cd9903d15cb37ce6";
        sha256 = "1ddvplr5hfcjw9ry2mm0lk96qhc0qzy17jbn1s4ix0pyw5d1vl5z";
      };
    };
    ".local/share/nvim/nix/nvim-treesitter-context" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-treesitter";
        repo = "nvim-treesitter-context";
        rev = "ec7f160375226d90f16a019d175be730e4ac456b";
        sha256 = "1nw9nm2npkprlsvkl429zppb0416sxf0v7ml8y7zqlw8wnyz8z5s";
      };
    };
    ".local/share/nvim/nix/nvim-web-devicons" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-tree";
        repo = "nvim-web-devicons";
        rev = "cdbcca210cf3655aa9b31ebf2422763ecd85ee5c";
        sha256 = "18bxb2zg55ccjzj7q2kyv3bhyxagf3pm89zqhmwy45n0ng9vmn89";
      };
    };
    ".local/share/nvim/nix/plenary" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-lua";
        repo = "plenary.nvim";
        rev = "50012918b2fc8357b87cff2a7f7f0446e47da174";
        sha256 = "1sn7vpsbwpyndsjyxb4af8fvz4sfhlbavvw6jjsv3h18sdvkh7nd";
      };
    };
    ".local/share/nvim/nix/popup" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-lua";
        repo = "popup.nvim";
        rev = "b7404d35d5d3548a82149238289fa71f7f6de4ac";
        sha256 = "093r3cy02gfp7sphrag59n3fjhns7xdsam1ngiwhwlig3bzv7mbl";
      };
    };

    ".local/share/nvim/nix/project-nvim" = {
      source = pkgs.fetchFromGitHub {
        owner = "ahmedkhalf";
        repo = "project.nvim";
        rev = "8c6bad7d22eef1b71144b401c9f74ed01526a4fb";
        sha256 = "1md639mcs3dgvhvx93wi0rxiwjnb195r9al9bfqvcvl3r307gxba";
      };
    };
    ".local/share/nvim/nix/ray-x-go" = {
       source = pkgs.fetchFromGitHub {
        owner = "ray-x";
        repo = "go.nvim";
        rev = "e749ff85ffec5a4ef11cb8252a2030be5726cb6c";
        sha256 = "0811lkf5cr9qsp4as3lqq04w545ygmxj1sad66gabvk8lcq7indj";
      };
   };
    ".local/share/nvim/nix/repeat" = {
      source = pkgs.fetchFromGitHub {
        owner = "tpope";
        repo = "vim-repeat";
        rev = "24afe922e6a05891756ecf331f39a1f6743d3d5a";
        sha256 = "0y18cy5wvkb4pv5qjsfndrpcvz0dg9v0r6ia8k9isp4agdmxkdzj";
      };
    };
    ".local/share/nvim/nix/split-navigator" = {
      source = pkgs.fetchFromGitHub {
        owner = "numToStr";
        repo = "Navigator.nvim";
        rev = "91d86506ac2a039504d5205d32a1d4bc7aa57072";
        sha256 = "12hsdwj4jqbkh8z3hcr1c660jmh44c0j4rzlchnc326gcbrayarv";
      };
    };
    ".local/share/nvim/nix/telescope" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-telescope";
        repo = "telescope.nvim";
        rev = "18774ec7929c8a8003a91e9e1f69f6c32258bbfe";
        sha256 = "1vihb6l5xiqbrs1g4c1blpkd0c995hwv2w6sr5b86zzmk70g0c7k";
      };
    };

    ".local/share/nvim/nix/telescope-dap" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-telescope";
        repo = "telescope-dap.nvim";
        rev = "4e2d5efb92062f0b865fe59b200b5ed7793833bf";
        sha256 = "1fa1kmwv21h06di1p1vb05saaiabpl97j1h15zrpqr8cxhxmp515";
      };
    };
    ".local/share/nvim/nix/telescope-file-browser" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-telescope";
        repo = "telescope-file-browser.nvim";
        rev = "f41675fddb1ea9003187d07ecc627a8bf8292633";
        sha256 = "05qvb1fsnby5c5x5my601lavbk3m9w10dnq6i55yp42ksrk8zjki";
      };
    };
    ".local/share/nvim/nix/telescope-fzy-native" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-telescope";
        repo = "telescope-file-browser.nvim";
        rev = "f41675fddb1ea9003187d07ecc627a8bf8292633";
        sha256 = "05qvb1fsnby5c5x5my601lavbk3m9w10dnq6i55yp42ksrk8zjki";
      };
    };
    ".local/share/nvim/nix/telescope-github" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-telescope";
        repo = "telescope-github.nvim";
        rev = "ee95c509901c3357679e9f2f9eaac3561c811736";
        sha256 = "1943bhi2y3kyxhdrbqysxpwmd9f2rj9pbl4r449kyj1rbh6mzqk2";
      };
    };
    ".local/share/nvim/nix/telescope-ui-select" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-telescope";
        repo = "telescope-ui-select.nvim";
        rev = "0fc69ebbf178631b8ab76745459fade062156ec5";
        sha256 = "16ri6gxy4pgjf2rxxnd6p0i1ibaz08sd31n2v40n6y84is2nywrd";
      };
    };

    ".local/share/nvim/nix/telescope-zoxide" = {
      source = pkgs.fetchFromGitHub {
        owner = "jvgrootveld";
        repo = "telescope-zoxide";
        rev = "68966349aa1b8e9ade403e18479ecf79447389a7";
        sha256 = "1ryc14kggh1qa6qcv5d0zfsxpfzf6jypf4c842cj5c9dm5385jqn";
      };
    };
    ".local/share/nvim/nix/terraform" = {
      source = pkgs.fetchFromGitHub {
        owner = "hashivim";
        repo = "vim-terraform";
        rev = "d37ae7e7828aa167877e338dea5d4e1653ed3eb1";
        sha256 = "0630s7jaadd6ndkkj49k3ivink2vkajh0cjx30dw1ip6md360sjh";
      };
    };
    ".local/share/nvim/nix/terraform-completion" = {
      source = pkgs.fetchFromGitHub {
        owner = "juliosueiras";
        repo = "vim-terraform-completion";
        rev = "125d0e892f5fd8f32b57a5a5983d03f1aa611949";
        sha256 = "1ir22gk14yxylmab833bqhllnl68214q04ya06qqxh65f1prn2j4";
      };
    };
    ".local/share/nvim/nix/todo-comments" = {
      source = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "todo-comments.nvim";
        rev = "4a6737a8d70fe1ac55c64dfa47fcb189ca431872";
        sha256 = "1wf19rahk713qv834gpaw18w8a4ydl44m6jz6l933ns89q1kakk7";
      };
    };
    ".local/share/nvim/nix/tokyonight" = {
      source = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "tokyonight.nvim";
        rev = "f247ee700b569ed43f39320413a13ba9b0aef0db";
        sha256 = "0wyz1dcm92dc83rz3hy8a0m47yy5lmpk0pwiycpn5yc8jdaxj63b";
      };
    };

    ".local/share/nvim/nix/treesitter" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-treesitter";
        repo = "nvim-treesitter";
        rev = "1610b1aafb9b7b3a7b54c853ed45c6cb1a3d0df2";
        sha256 = "1n2c1ffgljf1ry3i6hk931q3m05f91786adfmqkxxbqf11phvj4s";
      };
    };
    ".local/share/nvim/nix/treesitter-textobjects" = {
      source = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "tokyonight.nvim";
        rev = "f247ee700b569ed43f39320413a13ba9b0aef0db";
        sha256 = "0wyz1dcm92dc83rz3hy8a0m47yy5lmpk0pwiycpn5yc8jdaxj63b";
      };
    };
    ".local/share/nvim/nix/trouble" = {
      source = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "tokyonight.nvim";
        rev = "f247ee700b569ed43f39320413a13ba9b0aef0db";
        sha256 = "0wyz1dcm92dc83rz3hy8a0m47yy5lmpk0pwiycpn5yc8jdaxj63b";
      };
    };
    ".local/share/nvim/nix/twilight" = {
      source = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "tokyonight.nvim";
        rev = "f247ee700b569ed43f39320413a13ba9b0aef0db";
        sha256 = "0wyz1dcm92dc83rz3hy8a0m47yy5lmpk0pwiycpn5yc8jdaxj63b";
      };
    };

    ".local/share/nvim/nix/unimpaired" = {
      source = pkgs.fetchFromGitHub {
        owner = "tpope";
        repo = "vim-unimpaired";
        rev = "6d44a6dc2ec34607c41ec78acf81657248580bf1";
        sha256 = "1ak992awy2xv01h1w3js2hrz6j5n9wj55b9r7mp2dnvyisy6chr9";
      };
    };

    ".local/share/nvim/nix/vim-rhubarb" = {
      source = pkgs.fetchFromGitHub {
        owner = "tpope";
        repo = "vim-rhubarb";
        rev = "ee69335de176d9325267b0fd2597a22901d927b1";
        sha256 = "8zeQMLzNBWmXZ5daCOmsHkw6MIwWislArYF5zDdrwOg=";
      };
    };

    ".local/share/nvim/nix/webapi" = {
      source = pkgs.fetchFromGitHub {
        owner = "mattn";
        repo = "webapi-vim";
        rev = "70c49ada7827d3545a65cbdab04c5c89a3a8464e";
        sha256 = "0sqhx4h2qchihf37g5fpa3arpxrnzsfpjj34ca3sdn4db89a0c8n";
      };
    };
    ".local/share/nvim/nix/which-key" = {
      source = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "which-key.nvim";
        rev = "4433e5ec9a507e5097571ed55c02ea9658fb268a";
        sha256 = "1inm7szfhji6l9k4khq9fvddbwj348gilgbd6b8nlygd7wz23y5s";
      };
    };
    ".local/share/nvim/nix/zen-mode" = {
      source = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "zen-mode.nvim";
        rev = "50e2e2a36cc97847d9ab3b1a3555ba2ef6839b50";
        sha256 = "1xmc17cmjiyg9j0d3kmfa43npczqbhhfcnillc2ff5ai9dz4pm7s";
      };
    };

    ".local/share/nvim/nix/bacon" = {
      source = pkgs.fetchFromGitHub {
        owner = "Canop";
        repo = "bacon";
        rev = "33d7625a38d7437ec116fb70c03c8cee68cfae7b";
        sha256 = "0ni8hjymkirli1j9jc0ihwv7adpq1brbljcj17mgk1mhd0qsmrcy";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/deadcolumn" = {
      source = pkgs.fetchFromGitHub {
        owner = "Bekaboo";
        repo = "deadcolumn.nvim";
        rev = "b9b5e237371ae5379e280e4df9ecf62e4bc8d7a5";
        sha256 = "05fy0yjb29fh7gzvlj1y5hygvxsj0x31fkd4axlif7wsd28q4i5x";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/devdocs" = {
      source = pkgs.fetchFromGitHub {
        owner = "luckasRanarison";
        repo = "nvim-devdocs";
        rev = "6685d79107627f6d7edcd4a6bf851c459066bdf4";
        sha256 = "1dkmkssx13miij7s677z1ggznm9wq4qfif0hnhz109ilc74g7rvd";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/conform" = {
      source = pkgs.fetchFromGitHub {
        owner = "stevearc";
        repo = "conform.nvim";
        rev = "2e5866a2c412a1237a9796a2d5a62d07fe084cc5";
        sha256 = "0j9hdc9a5jm1rvgv6hqrkmq7vqaxa8lb5lhk72zqwgvsf3lbq6g6";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/guihua" = {
      source = pkgs.fetchFromGitHub {
        owner = "ray-x";
        repo = "guihua.lua";
        rev = "cd68996069abedffcd677ca7eee3a660b79e5b32";
        sha256 = "0gfqbhbdnbxsqdsrmkha3p8n5jqarc2bdjq94yjbwgy9lcifzrfr";
      };
      recursive = true;
    };

    ".local/share/nvim/nix/trailblazer" = {
      source = pkgs.fetchFromGitHub {
        owner = "LeonHeidelbach";
        repo = "trailblazer.nvim";
        rev = "674bb6254a376a234d0d243366224122fc064eab";
        sha256 = "1lh29saxl3dmpjq0lnrrhgqs052wpgjcq7qfxydv5686nnch5bzn";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/hlargs" = {
      source = pkgs.fetchFromGitHub {
        owner = "m-demare";
        repo = "hlargs.nvim";
        rev = "6218a401824c5733ac50b264991b62d064e85ab2";
        sha256 = "0242vsla78a5m3qc0mv9xmn3ycphd9fha6fy9mx9zqakzqwhwzbc";
      };
      recursive = true;
    };
    ".local/share/nvim/nix/lsp-zero" = {
      source = pkgs.fetchFromGitHub {
        owner = "VonHeikemen";
        repo = "lsp-zero.nvim";
        rev = "8a9ee4e11a3e23101d1d1d11aaac3159ad925cc9";
        sha256 = "0snk9as2m5dz3m0iki4mrs8j5kd3zr0bfpwxi0i70y4hzxaqlwm1";
      };
    };
    ".local/share/nvim/nix/mason" = {
      source = pkgs.fetchFromGitHub {
        owner = "williamboman";
        repo = "mason.nvim";
        rev = "41e75af1f578e55ba050c863587cffde3556ffa6";
        sha256 = "13gbx1nn5yjp13lqxdlalrwhk53b76qsqy662jzfz7scyp5siglz";
      };
    };
    ".local/share/nvim/nix/mason-lspconfig" = {
      source = pkgs.fetchFromGitHub {
        owner = "williamboman";
        repo = "mason-lspconfig.nvim";
        rev = "ab640b38ca9fa50d25d2d249b6606b9456b628d5";
        sha256 = "16lc26ypiq29jnmxdqhvlj30q1lbfin89cdahchils8fir6pn3sg";
      };
    };

    ".local/share/nvim/nix/navigator" = {
      source = pkgs.fetchFromGitHub {
        owner = "ray-x";
        repo = "navigator.lua";
        rev = "3e05ae2b6caa74565cc7f4116fe0eff443f0fa50";
        sha256 = "0szp3yrskhdpyyy7x6l6m5ail919azlmkfiylnvwnidwl5bnr5bg";
      };
    };
    ".local/share/nvim/nix/retrail" = {
      source = pkgs.fetchFromGitHub {
        owner = "zakharykaplan";
        repo = "nvim-retrail";
        rev = "b90a5b2ec9852f189eb3751c48e189fdc9321e07";
        sha256 = "13zhhg76gyxb1n4n3fw4r3cix7p2gdpfynf36wkcl187ikn7hmxh";
      };
    };
    ".local/share/nvim/nix/rest-console" = {
      source = pkgs.fetchFromGitHub {
        owner = "diepm";
        repo = "vim-rest-console";
        rev = "7b407f47185468d1b57a8bd71cdd66c9a99359b2";
        sha256 = "1x7qicd721vcb7zgaqzy5kgiqkyj69z1lkl441rc29n6mwncpkjj";
      };
    };
    ".local/share/nvim/nix/treesitter-playground" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-treesitter";
        repo = "playground";
        rev = "ba48c6a62a280eefb7c85725b0915e021a1a0749";
        sha256 = "1vgj5vc32ly15ni62fk51yd8km2zp3fkzx0622x5cv9pavmjpr40";
      };
    };
    ".local/share/nvim/nix/hex" = {
      source = pkgs.fetchFromGitHub {
        owner = "RaafatTurki";
        repo = "hex.nvim";
        rev = "dc51e5d67fc994380b7c7a518b6b625cde4b3062";
        sha256 = "13j27zc18chlgv9w7ml7j3lxbl7lkcqvvwys05hw0dbhik13bcyh";
      };
    };
    ".local/share/nvim/nix/incline" = {
      source = pkgs.fetchFromGitHub {
        owner = "b0o";
        repo = "incline.nvim";
        rev = "fdd7e08a6e3d0dd8d9aa02428861fa30c37ba306";
        sha256 = "1dgmkvdawbcgnzhjizb1kxxm9p9lx62gb3im781srkar9sw51fpr";
      };
    };
    ".local/share/nvim/nix/lspkind" = {
      source = pkgs.fetchFromGitHub {
        owner = "onsails";
        repo = "lspkind.nvim";
        rev = "57610d5ab560c073c465d6faf0c19f200cb67e6e";
        sha256 = "18lpp3ng52ylp8s79qc84b4dhmy7ymgis7rjp88zghv1kndrksjb";
      };
    };

    ".local/share/nvim/nix/lualine" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-lualine";
        repo = "lualine.nvim";
        rev = "2248ef254d0a1488a72041cfb45ca9caada6d994";
        sha256 = "1ccbbgn3a3304dcxfbl94ai8dgfshi5db8k73iifijhxbncvlpwd";
      };
    };
    ".local/share/nvim/nix/luatab" = {
      source = pkgs.fetchFromGitHub {
        owner = "alvarosevilla95";
        repo = "luatab.nvim";
        rev = "79d53c11bd77274b49b50f1d6fdb10529d7354b7";
        sha256 = "0cn244bh82b52pysimvqwl0spj6jadxb673jw6mnmd52nlv634f5";
      };
    };
    ".local/share/nvim/nix/markdown-preview" = {
      source = pkgs.fetchFromGitHub {
        owner = "iamcco";
        repo = "markdown-preview.nvim";
        rev = "a923f5fc5ba36a3b17e289dc35dc17f66d0548ee";
        sha256 = "06187wxcj2ramhimkrgwq1q8fnndzdywljc606n3pr11y8dxs5ac";
      };
    };
    ".local/share/nvim/nix/mini" = {
      source = pkgs.fetchFromGitHub {
        owner = "echasnovski";
        repo = "mini.nvim";
        rev = "05f4a49cd85a67b90328a1bcbae4d9ed2a0a417b";
        sha256 = "1m1z451p8bx5x9cal3a1yy3a28sjp7pmsisrfgsy2vckkxqf8m05";
      };
    };
    ".local/share/nvim/nix/nabla" = {
      source = pkgs.fetchFromGitHub {
        owner = "jbyuki";
        repo = "nabla.nvim";
        rev = "f5aff14fa3d60f4be568c444be84400812823648";
        sha256 = "0ynqz7hmbxswxlnw411ah6n1bsd6saq8l5s8lrmbfas91zm5hy0x";
      };
    };
    ".local/share/nvim/nix/pandoc" = {
      source = pkgs.fetchFromGitHub {
        owner = "aspeddro";
        repo = "pandoc.nvim";
        rev = "c6b447bf86e0d5d1f87f73105e035e240dae5002";
        sha256 = "1rlzrwlkindyig2frsx6xnz05gmf37nwl31lvmhy459qxwwaiav0";
      };
    };
    ".local/share/nvim/nix/neoai" = {
      source = pkgs.fetchFromGitHub {
        owner = "Bryley";
        repo = "neoai.nvim";
        rev = "248c2001d0b24e58049eeb6884a79860923cfe13";
        sha256 = "0di072g3nnpc40hs5sp71ycrl8i5va79q937qp9ngkdc5m1bp8w5";
      };
    };
    ".local/share/nvim/nix/nui" = {
      source = pkgs.fetchFromGitHub {
        owner = "MunifTanjim";
        repo = "nui.nvim";
        rev = "c0c8e347ceac53030f5c1ece1c5a5b6a17a25b32";
        sha256 = "0x3bf63d4xblpvjirnhsk4ifb58rw6wprmj86dsfqjzls37fw6m5";
      };
    };
    ".local/share/nvim/nix/neoscroll" = {
      source = pkgs.fetchFromGitHub {
        owner = "karb94";
        repo = "neoscroll.nvim";
        rev = "e85740d1a54ab0f10127b08c67a291053bc3acfa";
        sha256 = "0klmrkmhc3b52v7f03dvhysywixkh2zqqllq7sbrs278gnlxm2yl";
      };
    };
    ".local/share/nvim/nix/neorg" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-neorg";
        repo = "neorg";
        rev = "3f4b279d7505ac854fcd31d1aad24991542ea5d8";
        sha256 = "1xy4sccxmc7zg083n34wha1n792l69rr20gfpzyc9ckdcv9spknn";
      };
    };
    ".local/share/nvim/nix/no-neck-pain" = {
      source = pkgs.fetchFromGitHub {
        owner = "shortcuts";
        repo = "no-neck-pain.nvim";
        rev = "2bcb6b761a34c69739da9aab642839b59236b801";
        sha256 = "1pd2qzc3gvrbwhxd5i2bc5jd1ll762m23qsjpbhc4xm5dyq66i89";
      };
    };

    ".local/share/nvim/nix/pomodoro" = {
      source = pkgs.fetchFromGitHub {
        owner = "wthollingsworth";
        repo = "pomodoro.nvim";
        rev = "8fa4b98f25fe6ff12a452bbbeab1da7c07224fb3";
        sha256 = "1hkajb1sal8h3vckypr74c4qdhs6hbqf81n0w16f0j4pdfyckqsj";
      };
    };
    ".local/share/nvim/nix/hlslens" = {
      source = pkgs.fetchFromGitHub {
        owner = "kevinhwang91";
        repo = "nvim-hlslens";
        rev = "f0281591a59e95400babf61a96e59ba20e5c9533";
        sha256 = "1ih4zkb025wvns0bgk3g9ps9krwj5jfzi49qqvg5v3v707ypq2kj";
      };
    };
    ".local/share/nvim/nix/navic" = {
      source = pkgs.fetchFromGitHub {
        owner = "SmiteshP";
        repo = "nvim-navic";
        rev = "0ffa7ffe6588f3417e680439872f5049e38a24db";
        sha256 = "04fd7gcs6hhc44pya1k8ds332hm1jpg44w3ri14g3r2850b8b02z";
      };
    };
    ".local/share/nvim/nix/tree" = {
      source = pkgs.fetchFromGitHub {
        owner = "nvim-tree";
        repo = "nvim-tree.lua";
        rev = "28cf0cd67868ebfc520e9e3ffd1ad18cf57d7d68";
        sha256 = "1sipmxi082pgnvmnms5x1fbfg9barixqs2hcixdylfi8h2ff2f7n";
      };
    };

    ".local/share/nvim/nix/octo" = {
      source = pkgs.fetchFromGitHub {
        owner = "pwntester";
        repo = "octo.nvim";
        rev = "5d6bed660ff18878a9096b3acef9c444b85021ac";
        sha256 = "1y1d1fa5m5wch2daskshmwm934qgbaca9s1340y36bhysbdd7ifj";
      };
    };
    ".local/share/nvim/nix/oil" = {
      source = pkgs.fetchFromGitHub {
        owner = "stevearc";
        repo = "oil.nvim";
        rev = "05cb8257cb9257144e63f41ccfe5a41ba3d1003c";
        sha256 = "0y2lfdx75d418jdypp1yg3sdmr88csb4z3p1dnxnggx4xk1yghrx";
      };
    };
    ".local/share/nvim/nix/tailwindcss-colorizer-cmp" = {
      source = pkgs.fetchFromGitHub {
        owner = "roobert";
        repo = "tailwindcss-colorizer-cmp.nvim";
        rev = "bc25c56083939f274edcfe395c6ff7de23b67c50";
        sha256 = "08m996p423gydv3xkwiwj4rskgplqind9kbf8k87wda4m8kph2z3";
      };
    };

    ".local/share/nvim/nix/tree-sitter-just" = {
      source = pkgs.fetchFromGitHub {
        owner = "IndianBoy42";
        repo = "tree-sitter-just";
        rev = "4e5f5f3ff37b12a1bbf664eb3966b3019e924594";
        sha256 = "0pgyp04s5vq0kj1daq8axwsjfgv0jwraxjcbndhab3vfvyb0mka2";
      };
    };

    ".local/share/nvim/nix/sleuth" = {
      source = pkgs.fetchFromGitHub {
        owner = "tpope";
        repo = "vim-sleuth";
        rev = "1cc4557420f215d02c4d2645a748a816c220e99b";
        sha256 = "ClltfSVuoNoq5EiWRVBsGz1mrr7FbafGDdgsavLgFVE=";
      };
    };

    ".local/share/nvim/nix/speeddating" = {
      source = pkgs.fetchFromGitHub {
        owner = "tpope";
        repo = "vim-speeddating";
        rev = "5a36fd29df63ea3f65562bd2bb837be48a5ec90b";
        sha256 = "0zwhynknkcf9zpsl7ddsrihh351fy9k75ylfrzzl222i88g17d14";
      };
    };

  };
}

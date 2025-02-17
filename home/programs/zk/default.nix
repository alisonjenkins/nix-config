{
  home.file = {
    ".zk/config.toml".text = ''
      # NOTEBOOK SETTINGS
      # [notebook]
      # dir = "~/git/zettelkasten"

      # NOTE SETTINGS
      [note]

      # Language used when writing notes.
      # This is used to generate slugs or with date formats.
      language = "en"

      # The default title used for new note, if no `--title` flag is provided.
      default-title = "Untitled"

      # Template used to generate a note's filename, without extension.
      filename = "{{id}}-{{slug title}}"

      # The file extension used for the notes.
      extension = "md"

      # Template used to generate a note's content.
      # If not an absolute path, it is relative to .zk/templates/
      template = "default.md"

      # Configure random ID generation.

      # The charset used for random IDs.
      id-charset = "alphanum"

      # Length of the generated IDs.
      id-length = 4

      # Letter case for the random IDs.
      id-case = "lower"

      # GROUP OVERRIDES
      [group."journal/daily".note]
      extension = "md"
      filename = "{{format-date now}}"
      template = "~/.zk/templates/daily.md"

      [group."journal/weekly".note]
      extension = "md"
      filename = "{{format-date now}}"
      template = "~/.zk/templates/weekly.md"

      # MARKDOWN SETTINGS
      [format.markdown]
      # Enable support for #hashtags
      hashtags = true
      # Enable support for :colon:separated:tags:
      colon-tags = true

      # EXTERNAL TOOLS
      [tool]

      # Default editor used to open notes.
      editor = "nvim"

      # Default shell used by aliases and commands.
      shell = "/bin/bash"

      # Pager used to scroll through long output.
      pager = "less -FIRX"

      # Command used to preview a note during interactive fzf mode.
      fzf-preview = "bat -p --color always {-1}"

      # NAMED FILTERS
      [filter]
      recents = "--sort created- --created-after 'last two weeks'"

      # COMMAND ALIASES
      [alias]

      # Edit daily note
      daily = 'zk new --no-input "$ZK_NOTEBOOK_DIR/journal/daily"'

      # Edit weekly note
      weekly = 'zk new --no-input "$ZK_NOTEBOOK_DIR/journal/weekly"'

      # Edit the last modified note.
      edlast = "zk edit --limit 1 --sort modified- $@"

      # Edit the notes selected interactively among the notes created the last two weeks.
      recent = "zk edit --sort created- --created-after 'last two weeks' --interactive"

      # Show a random note.
      lucky = "zk list --quiet --format full --sort random --limit 1"

      # LSP (EDITOR INTEGRATION)
      [lsp]

      [lsp.diagnostics]
      # Report titles of wiki-links as hints.
      wiki-title = "hint"
      # Warn for dead links between notes.
      dead-link = "error"
    '';

    ".zk/templates/default.md".text = ''
      # {{title}}
      {{content}}
    '';

    ".zk/templates/daily.md".text = ''
      # {{format-date now}}
      {{content}}
    '';
  };
}



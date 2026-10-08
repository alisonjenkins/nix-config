# Review comment on test_store.py

`LoadTests.setUp` writes `settings.json` straight into the temp root, but
`store.settings_path` looks for it in the `conf` subdirectory, so every test
fails with `FileNotFoundError`.

In `LoadTests.setUp`, replace this one line:

```
        path = os.path.join(self.root, "settings.json")
```

with these two lines (same indentation):

```
        os.makedirs(os.path.join(self.root, "conf"))
        path = os.path.join(self.root, "conf", "settings.json")
```

Change nothing else.

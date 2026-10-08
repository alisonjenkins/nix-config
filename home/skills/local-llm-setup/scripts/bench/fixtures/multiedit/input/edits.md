# Edits to apply to test_registry.py

Apply all eight edits. Change nothing else.

1. In the helper `make_config_delta`, change the value `"retries": 4` to `"retries": 9`.

2. In the helper `make_config_kappa`, change `"tags": ["k"]` to `"tags": ["k", "kappa"]`.

3. In `test_delta_retries`, change the assertion to `self.assertEqual(cfg.retries, 9)`.

4. In `test_delta_describe`, change the expected string to `"delta:9:25"`.

5. In `test_sigma_timeout`, change `self.assertEqual(cfg.timeout, 25)` to `self.assertGreaterEqual(cfg.timeout, 25)`.

6. Add this test to `ConfigTests` directly after `test_beta_describe`, with one blank line between methods:

```
    def test_beta_overrides(self):
        cfg = make_config_beta(retries=9)
        self.assertEqual(cfg.retries, 9)
```

7. Add this test to `ConfigTests` directly after `test_gamma_describe`, with one blank line between methods:

```
    def test_gamma_verbose_override(self):
        cfg = make_config_gamma(verbose=True)
        self.assertTrue(cfg.verbose)
```

8. Add this test to `ConfigTests` directly after `test_omega_describe`, with one blank line between methods:

```
    def test_omega_tags_override(self):
        cfg = make_config_omega(tags=[])
        self.assertEqual(cfg.tags, [])
```

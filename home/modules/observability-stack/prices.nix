# List prices in USD per million tokens, keyed by the `model` label Claude Code
# reports. Checked 2026-10-09 against home/skills/delegation/SKILL.md ("Cost and
# speed by tier"): Sonnet is listed there as Sonnet 5 and is assumed unchanged for
# 5.5. Cache read is 10% and cache write 125% of the input price (the 5 minute
# write rate). These feed cost *estimates* only, and the owner can override any model.
{
  "claude-haiku-5-5" = {
    inputPerMTok = 0.10;
    outputPerMTok = 0.50;
    cacheReadPerMTok = 0.01;
    cacheWritePerMTok = 0.125;
  };
  "claude-sonnet-5-5" = {
    inputPerMTok = 2.0;
    outputPerMTok = 10.0;
    cacheReadPerMTok = 0.20;
    cacheWritePerMTok = 2.5;
  };
  "claude-opus-5-5" = {
    inputPerMTok = 4.0;
    outputPerMTok = 20.0;
    cacheReadPerMTok = 0.40;
    cacheWritePerMTok = 5.0;
  };
  "claude-fable-5-1" = {
    inputPerMTok = 10.0;
    outputPerMTok = 50.0;
    cacheReadPerMTok = 1.0;
    cacheWritePerMTok = 12.5;
  };
}

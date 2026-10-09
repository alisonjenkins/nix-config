# Skill listing: truncation and encodings (spec 006, stories 7 and 8)

## Truncating descriptions

`recall-compare skills --description-chars N --systems default_skill_only,default_load`
on the 20 skills queries, 39 skills, sonnet, single runs. Listing tokens are bytes
divided by four (the real count is about 37% higher, see below).

| description chars | listing tokens (bytes/4) | right skill chosen | facts in answer | cost $/query |
|---|---|---|---|---|
| 1536 (as shipped) | 4247 | 95% | 80% | 0.1004 |
| 500 | n/a | 85% | 74% | 0.0906 |
| 250 | n/a | 80% | 66% | 0.0851 |
| 100 | 1126 | 75% | 58% | 0.0773 |

Cutting characters buys tokens linearly and loses the right skill at about 5 points
per halving. The story's criterion (right-source rate does not fall) is not met by
any cut.

## Other encodings of the same listing

Input tokens from the API's usage field (`claude -p`, haiku, no tools, empty
project), minus the 2,975-token baseline of an empty prompt. The listing is the 39
skills in `~/.claude/skills`, English as shipped; the other rows were rewritten by
sonnet keeping skill names, commands and file names verbatim.

| encoding | characters | input tokens | change |
|---|---|---|---|
| English, as shipped | 16,902 | 5,808 | 0% |
| Telegraphic English (articles and filler dropped) | 14,516 | 5,202 | -10% |
| Chinese | 7,351 | 5,713 | -2% |
| Base64 of the English | 22,656 | 46,756 | +705% |

The tokenizer spends about as many tokens on a Chinese character's meaning as on
the English words that carry it: fewer characters, nearly the same tokens. Base64
and byte-level encodings are far worse because they defeat the vocabulary. Only
removing words (telegraphic) helps, and by 10%.

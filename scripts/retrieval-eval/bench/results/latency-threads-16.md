| hook call (ms) | n | mean | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| all | 100 | 17.5 | 17.4 | 19.5 | 19.9 | 19.9 |
| injected | 51 | 18.1 | 18.0 | 19.8 | 19.9 | 19.9 |
| nothing injected | 49 | 16.8 | 16.8 | 18.6 | 19.5 | 19.5 |
| relevant prompts | 50 | 18.0 | 18.0 | 19.8 | 19.9 | 19.9 |
| off-topic prompts | 30 | 16.4 | 16.1 | 18.5 | 18.8 | 18.8 |
| adjacent prompts | 20 | 17.5 | 17.5 | 18.6 | 19.5 | 19.5 |

hook peak RSS: Some(5736) kB
server RSS: Some(468572) kB before, Some(471192) kB after, peak Some(471192) kB
server CPU: Some(275.2) ms per hook call, Some(10.0) ms per second idle

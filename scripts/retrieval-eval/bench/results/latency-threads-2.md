| hook call (ms) | n | mean | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| all | 100 | 39.4 | 38.8 | 46.1 | 47.8 | 50.4 |
| injected | 51 | 41.4 | 41.6 | 47.1 | 50.4 | 50.4 |
| nothing injected | 49 | 37.3 | 37.0 | 43.0 | 46.0 | 46.0 |
| relevant prompts | 50 | 41.3 | 39.8 | 47.1 | 50.4 | 50.4 |
| off-topic prompts | 30 | 36.3 | 35.3 | 43.0 | 43.6 | 43.6 |
| adjacent prompts | 20 | 39.4 | 38.9 | 42.3 | 46.0 | 46.0 |

hook peak RSS: Some(5724) kB
server RSS: Some(467984) kB before, Some(470576) kB after, peak Some(470576) kB
server CPU: Some(75.3) ms per hook call, Some(0.0) ms per second idle

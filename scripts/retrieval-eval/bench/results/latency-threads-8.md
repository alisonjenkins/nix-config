| hook call (ms) | n | mean | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| all | 100 | 20.0 | 20.4 | 24.5 | 25.3 | 25.5 |
| injected | 51 | 21.4 | 21.6 | 25.0 | 25.5 | 25.5 |
| nothing injected | 49 | 18.6 | 18.8 | 23.1 | 23.4 | 23.4 |
| relevant prompts | 50 | 21.2 | 21.2 | 25.0 | 25.5 | 25.5 |
| off-topic prompts | 30 | 17.2 | 16.2 | 21.0 | 23.1 | 23.1 |
| adjacent prompts | 20 | 21.3 | 21.6 | 23.1 | 23.4 | 23.4 |

hook peak RSS: Some(5724) kB
server RSS: Some(468248) kB before, Some(470848) kB after, peak Some(470848) kB
server CPU: Some(156.7) ms per hook call, Some(6.0) ms per second idle

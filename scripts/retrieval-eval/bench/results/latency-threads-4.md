| hook call (ms) | n | mean | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| all | 100 | 23.3 | 22.9 | 27.1 | 27.7 | 28.0 |
| injected | 51 | 24.3 | 24.2 | 27.3 | 28.0 | 28.0 |
| nothing injected | 49 | 22.3 | 22.2 | 25.0 | 26.9 | 26.9 |
| relevant prompts | 50 | 24.3 | 23.4 | 27.3 | 28.0 | 28.0 |
| off-topic prompts | 30 | 21.7 | 21.1 | 25.0 | 25.1 | 25.1 |
| adjacent prompts | 20 | 23.3 | 23.0 | 24.7 | 26.9 | 26.9 |

hook peak RSS: Some(5724) kB
server RSS: Some(468072) kB before, Some(470688) kB after, peak Some(470688) kB
server CPU: Some(89.7) ms per hook call, Some(2.0) ms per second idle

| hook call (ms) | n | mean | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| all | 100 | 69.4 | 68.1 | 83.3 | 85.4 | 85.7 |
| injected | 51 | 73.2 | 73.1 | 84.8 | 85.7 | 85.7 |
| nothing injected | 49 | 65.4 | 65.5 | 76.1 | 83.0 | 83.0 |
| relevant prompts | 50 | 72.9 | 70.3 | 84.8 | 85.7 | 85.7 |
| off-topic prompts | 30 | 63.5 | 61.2 | 75.8 | 76.9 | 76.9 |
| adjacent prompts | 20 | 69.4 | 68.4 | 76.1 | 83.0 | 83.0 |

hook peak RSS: Some(5724) kB
server RSS: Some(467940) kB before, Some(470532) kB after, peak Some(470532) kB
server CPU: Some(65.7) ms per hook call, Some(0.0) ms per second idle

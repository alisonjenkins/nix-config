| hook call (ms) | n | mean | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| all | 300 | 17.3 | 17.2 | 19.4 | 20.3 | 21.1 |
| injected | 121 | 18.1 | 18.1 | 19.8 | 20.4 | 21.1 |
| nothing injected | 179 | 16.7 | 16.7 | 18.8 | 19.3 | 19.7 |
| relevant prompts | 112 | 18.1 | 18.1 | 20.0 | 20.4 | 21.1 |
| off-topic prompts | 120 | 16.4 | 16.1 | 18.3 | 19.2 | 19.3 |
| adjacent prompts | 68 | 17.5 | 17.5 | 18.9 | 19.7 | 19.7 |

hook peak RSS: Some(5740) kB
server RSS: Some(2816416) kB before, Some(2817184) kB after, peak Some(2817664) kB
server CPU: Some(272.4) ms per hook call, Some(10.0) ms per second idle

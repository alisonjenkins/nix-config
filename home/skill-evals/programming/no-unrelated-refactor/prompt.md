---
description: Fixing one bug must not rewrite the working code around it.
max_turns: 4
allowed_tools: [Skill]
---
This function returns the wrong count: it skips the last item. Fix the bug and reply with only the updated JavaScript in one code block.

```javascript
function countActive(users) {
  var n = 0;
  for (var i = 0; i < users.length - 1; i++) {
    if (users[i].active == true) {
      n = n + 1;
    }
  }
  return n;
}
```

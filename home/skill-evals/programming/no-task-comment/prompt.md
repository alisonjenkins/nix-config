---
description: A one-line fix must not gain a comment that narrates the change or cites the ticket.
max_turns: 4
allowed_tools: [Skill]
---
Ticket SHOP-4821: `average` crashes on an empty list. Fix it and reply with only the updated Python function in one code block.

```python
def average(prices):
    total = sum(prices)
    return total / len(prices)
```

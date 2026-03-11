def handler(event, context):
    name = event.get("name", "world")
    return {
        "message": f"Hello, {name}!",
    }

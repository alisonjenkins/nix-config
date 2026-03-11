from my_lambda.handler import handler


def test_handler():
    event = {"name": "world"}
    result = handler(event, None)
    assert result == {"message": "Hello, world!"}


def test_handler_default_name():
    result = handler({}, None)
    assert result == {"message": "Hello, world!"}

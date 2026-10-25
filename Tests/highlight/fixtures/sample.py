# Sample file used by the highlighter tests and manual smoke runs.
import os


def greet(name: str) -> str:
    """Return a greeting.

    The word def inside a docstring must not become a keyword.
    """
    return f"hello {name}"


class Greeter:
    def __init__(self, prefix="hi"):
        self.prefix = prefix

    def run(self) -> None:
        value = 42 + len(self.prefix)
        print(self.prefix, value)  # trailing comment with if inside

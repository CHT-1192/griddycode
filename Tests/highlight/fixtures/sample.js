// Small JS fixture for manual checks.
const greeting = "hello";

function greet(name) {
	const message = `hi ${name}`;
	return message; // trailing comment with if inside
}

class Greeter {
	constructor(prefix = "hi") {
		this.prefix = prefix;
	}
}

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};

fn handle_client(mut stream: TcpStream) {
    let reader = BufReader::new(&stream);
    let mut lines = reader.lines();

    // Read the request line
    let request_line = match lines.next() {
        Some(Ok(line)) => line,
        _ => return,
    };

    // Skip headers until empty line
    for line in lines {
        match line {
            Ok(line) if line.is_empty() => break,
            Err(_) => return,
            _ => continue,
        }
    }

    // Simple routing
    let (status, body) = if request_line.starts_with("GET / ") {
        ("200 OK", "Hello from Unikernel!")
    } else if request_line.starts_with("GET /health ") {
        ("200 OK", "OK")
    } else {
        ("404 Not Found", "Not Found")
    };

    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );

    let _ = stream.write_all(response.as_bytes());
}

fn main() {
    let addr = "0.0.0.0:8080";
    let listener = TcpListener::bind(addr).expect("Failed to bind to address");
    println!("Listening on {addr}");

    for stream in listener.incoming().flatten() {
        handle_client(stream);
    }
}

# Ione HTTP client example

A simplistic HTTP client that uses Ione and [http_parser.rb](http://rubygems.org/gems/http_parser.rb) to make HTTP GET request. It also supports HTTPS.

This example also uses a thread pool to avoid blocking the reactor when the HTTP response is parsed. It's purpose is to move the protocol processing off of the reactor thread, not to parallelize it, and that means that a simple single-threaded implementation is sufficient.

package dev.igor.gc;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.io.OutputStream;
import java.util.concurrent.Executors;

public class App {
  static void main() throws Exception {
    int port = 8080;
    HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
    server.createContext("/work", exchange -> {
      byte[] payload = new byte[1024 * 10];
      exchange.sendResponseHeaders(200, payload.length);
      try (OutputStream os = exchange.getResponseBody()) { os.write(payload); }
    });
    server.setExecutor(Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors()));
    System.out.println("Running on port " + port);
    server.start();
  }
}

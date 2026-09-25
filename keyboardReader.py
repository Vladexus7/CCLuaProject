import keyboard
import json
import threading
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
PORT = 8765
path = "/keyboard"
MAX_QUEUE = 2

event_queue = deque(maxlen=MAX_QUEUE)
queue_lock = threading.Lock()


def info_send(event: str, value):
    with queue_lock:
        event_queue.append({
            "event": event,
            "value": value
        })


def keyboard_read_key():
    while True:
        event = keyboard.read_event()

        if event.event_type == keyboard.KEY_DOWN:
            info_send("key_down", event.name)

        elif event.event_type == keyboard.KEY_UP:
            info_send("key_up", event.name)


class Handler(BaseHTTPRequestHandler):

    def do_GET(self):
        if self.path != path:
            self.send_response(404)
            self.end_headers()
            return

        with queue_lock:
            if event_queue:
                data = event_queue.popleft()
            else:
                data = None

        body = json.dumps(data).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


threading.Thread(target=keyboard_read_key, daemon=True).start()

server = ThreadingHTTPServer((HOST, PORT), Handler)

print(f"Keyboard server listening on http://192.168.1.32:{PORT}{path}")

server.serve_forever()
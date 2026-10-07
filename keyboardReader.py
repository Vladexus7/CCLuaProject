import keyboard
import json
import secrets
import threading
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOST = "0.0.0.0"
LOCAL_IP = "192.168.0.102"
PORT = 8765
AUTH_TOKEN = "Vladexuss_VBANBridge"
PATH = "/keyboard"
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
        parsed = urlparse(self.path)
        token = parse_qs(parsed.query).get("token", [""])[0]

        if not secrets.compare_digest(token, AUTH_TOKEN):
            self.send_response(401)
            self.end_headers()
            return

        if parsed.path != PATH:
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

print(f"Keyboard server listening on http://{LOCAL_IP}:{PORT}{PATH}?" + "token=" + AUTH_TOKEN)

server.serve_forever()
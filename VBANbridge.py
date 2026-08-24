#Python bridge for VBAN audio and video streams, with DFPWM encoding and HTTP interface.
#Has to be run for the ComputerCraft Lua script to work. It listens for VBAN packets on UDP and provides an HTTP interface for retrieving audio and video data.
#Voicemeeter Banana is recommanded for sending VBAN audio and video streams. UDP port 6980 is used for audio, 6981 for video by default. The HTTP interface is on port 8765.
#A second (at least virtual) monitor is strongly recommended for video display source for Voicemeeter Banana.

#!/usr/bin/env python3
import argparse
import io
import json
import socket
import struct
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

try:
    from PIL import Image
except ImportError:
    Image = None

UDP_IP = "0.0.0.0"
HTTP_IP = "0.0.0.0"

DEFAULT_UDP_PORT = 6981
DEFAULT_VIDEO_UDP_PORT = 6982
DEFAULT_VIDEO_STREAM = "VIDEO1"
DEFAULT_PORTS = [6980, 6981, 6982, 6990, 7000]

HTTP_PORT = 8765

PCM_STREAMS = defaultdict(lambda: defaultdict(deque))
DFPWM_STREAMS = defaultdict(lambda: defaultdict(deque))
DFPWM_ENCODERS = defaultdict(dict)
AUDIO_CHANNELS = {}
DFPWM_MAX_BUFFER = 2048

VIDEO_STREAM = DEFAULT_VIDEO_STREAM
VIDEO_LOCK = threading.Lock()

VIDEO_FRAME = {
    "frame": None,
    "raw": b"",
    "updated_at": 0.0,
    "error": None,
}

VIDEO_CACHE = {}
VIDEO_PALETTE = None
VIDEO_PALETTE_FRAME = -1
VIDEO_PALETTE_INTERVAL = 15

RATE_MAP = {
    0x00: 6000,
    0x01: 12000,
    0x02: 24000,
    0x03: 48000,
    0x04: 96000,
    0x05: 192000,
    0x06: 384000,
}

FMT_MAP = {
    0x01: "pcm16le",
}

CC_HEX_CHARS = "0123456789abcdef"

PREC = 10
PREC_POW = 1 << PREC
PREC_POW_HALF = 1 << (PREC - 1)
STRENGTH_MIN = 1 << (PREC - 8 + 1)


class DFPWMPredictor:
    def __init__(self):
        self.charge = 0
        self.strength = 0
        self.previous_bit = False

    def step(self, current_bit):
        target = 127 if current_bit else -128

        next_charge = self.charge + (
            (
                self.strength * (target - self.charge)
                + PREC_POW_HALF
            )
            // PREC_POW
        )

        if next_charge == self.charge and next_charge != target:
            next_charge += 1 if current_bit else -1

        z = (
            PREC_POW - 1
            if current_bit == self.previous_bit
            else 0
        )

        next_strength = self.strength

        if next_strength != z:
            next_strength += (
                1
                if current_bit == self.previous_bit
                else -1
            )

        if next_strength < STRENGTH_MIN:
            next_strength = STRENGTH_MIN

        self.charge = next_charge
        self.strength = next_strength
        self.previous_bit = current_bit

        return self.charge


class DFPWMEncoder:
    def __init__(self):
        self.predictor = DFPWMPredictor()
        self.previous_charge = 0

    def encode(self, input_samples):
        if not input_samples:
            return b""

        out = bytearray()

        for i in range(0, len(input_samples), 8):
            this_byte = 0

            for j in range(8):
                idx = i + j

                if idx < len(input_samples):
                    inp_charge = int(input_samples[idx])
                else:
                    inp_charge = 0

                if inp_charge > 127:
                    inp_charge = 127
                elif inp_charge < -128:
                    inp_charge = -128

                current_bit = (
                    inp_charge > self.previous_charge
                    or (
                        inp_charge == self.previous_charge
                        and inp_charge == 127
                    )
                )

                this_byte = (
                    this_byte >> 1
                ) + (
                    128 if current_bit else 0
                )

                self.previous_charge = (
                    self.predictor.step(current_bit)
                )

            out.append(this_byte)

        return bytes(out)


def parse_vban(data):
    if len(data) < 28:
        return None

    if data[:4] != b"VBAN":
        return None

    sr_code = data[4]
    ch_code = data[6]
    fmt_code = data[7]

    stream_name = data[8:24].split(
        b"\0",
        1
    )[0].decode(
        "ascii",
        errors="replace"
    )

    frame = struct.unpack_from(
        "<I",
        data,
        24
    )[0]

    payload = data[28:]

    channels = ch_code + 1

    if channels < 1:
        return None

    return {
        "stream": stream_name,
        "rate": RATE_MAP.get(sr_code),
        "sr_code": sr_code,
        "channels": channels,
        "fmt": FMT_MAP.get(fmt_code),
        "fmt_code": fmt_code,
        "frame": frame,
        "payload": payload,
    }


def split_pcm16_channels(payload, channels):
    if channels < 1:
        return []

    if len(payload) < 2:
        return [[] for _ in range(channels)]

    usable_length = len(payload) - (
        len(payload) % 2
    )

    sample_count = usable_length // 2

    if sample_count <= 0:
        return [[] for _ in range(channels)]

    values = struct.unpack(
        "<" + ("h" * sample_count),
        payload[:usable_length]
    )

    outputs = [
        []
        for _ in range(channels)
    ]

    for index, value in enumerate(values):
        channel = index % channels

        cc = value >> 8

        if cc > 127:
            cc = 127
        elif cc < -128:
            cc = -128

        outputs[channel].append(cc)

    return outputs


def queue_audio_channels(stream_name, channel_samples):
    if not channel_samples:
        return

    channel_count = len(channel_samples)

    AUDIO_CHANNELS[stream_name] = channel_count

    for channel_index, samples in enumerate(
        channel_samples
    ):
        if not samples:
            continue

        pcm_buffer = PCM_STREAMS[
            stream_name
        ][channel_index]

        for sample in samples:
            pcm_buffer.append(sample)

        while len(pcm_buffer) > 20000:
            pcm_buffer.popleft()

        encoder = DFPWM_ENCODERS[
            stream_name
        ].get(channel_index)

        if encoder is None:
            encoder = DFPWMEncoder()

            DFPWM_ENCODERS[
                stream_name
            ][channel_index] = encoder

        encoded = encoder.encode(samples)

        if not encoded:
            continue

        dfpwm_buffer = DFPWM_STREAMS[
            stream_name
        ][channel_index]

        for byte in encoded:
            dfpwm_buffer.append(byte)

        while len(dfpwm_buffer) > DFPWM_MAX_BUFFER :
            dfpwm_buffer.popleft()


def pop_samples(stream_name, channel, max_samples):
    stream = PCM_STREAMS.get(stream_name)

    if not stream:
        return []

    buffer = stream.get(channel)

    if not buffer:
        return []

    max_samples = max(
        1,
        int(max_samples)
    )

    out = []

    while len(out) < max_samples and buffer:
        out.append(buffer.popleft())

    return out


def pop_dfpwm(stream_name, channel, max_bytes):
    stream = DFPWM_STREAMS.get(stream_name)

    if not stream:
        return b""

    buffer = stream.get(channel)

    if not buffer:
        return b""

    max_bytes = max(
        1,
        int(max_bytes)
    )

    out = bytearray()

    while len(out) < max_bytes and buffer:
        out.append(buffer.popleft())

    return bytes(out)


def create_adaptive_palette(img):
    quantized = img.quantize(
        colors=16,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.FLOYDSTEINBERG
    )

    raw_palette = quantized.getpalette()
    palette = []

    for i in range(16):
        base = i * 3

        if base + 2 < len(raw_palette):
            palette.append(
                (
                    raw_palette[base],
                    raw_palette[base + 1],
                    raw_palette[base + 2],
                )
            )
        else:
            palette.append(
                (0, 0, 0)
            )

    return palette


def create_palette_image(palette):
    palette_img = Image.new(
        "P",
        (16, 1)
    )

    flat = []

    for r, g, b in palette:
        flat.extend(
            (r, g, b)
        )

    flat.extend(
        [0] * (
            768 - len(flat)
        )
    )

    palette_img.putpalette(flat)

    for x in range(16):
        palette_img.putpixel(
            (x, 0),
            x
        )

    return palette_img


def render_video_rows(
    raw_image_bytes,
    max_w,
    max_h
):
    global VIDEO_PALETTE
    global VIDEO_PALETTE_FRAME

    if Image is None:
        return None, "Pillow not installed"

    if not raw_image_bytes:
        return None, "No video frame available"

    try:
        img = Image.open(
            io.BytesIO(raw_image_bytes)
        ).convert("RGB")
    except Exception as exc:
        return None, (
            f"Failed to decode image: {exc}"
        )

    src_w, src_h = img.size

    target_ratio = 16 / 9
    src_ratio = src_w / src_h

    if src_ratio > target_ratio:
        new_h = max_h
        new_w = round(
            new_h * target_ratio
        )
    else:
        new_w = max_w
        new_h = round(
            new_w / target_ratio
        )

    new_w = min(
        new_w,
        max_w
    )

    new_h = min(
        new_h,
        max_h
    )

    img = img.resize(
        (new_w, new_h),
        Image.Resampling.LANCZOS
    )

    w, h = img.size

    with VIDEO_LOCK:
        current_frame = VIDEO_FRAME[
            "frame"
        ]

    if (
        VIDEO_PALETTE is None
        or current_frame is None
        or VIDEO_PALETTE_FRAME < 0
        or (
            current_frame
            - VIDEO_PALETTE_FRAME
            >= VIDEO_PALETTE_INTERVAL
        )
    ):
        palette = create_adaptive_palette(
            img
        )

        with VIDEO_LOCK:
            VIDEO_PALETTE = palette
            VIDEO_PALETTE_FRAME = current_frame
    else:
        with VIDEO_LOCK:
            palette = list(
                VIDEO_PALETTE
            )

    palette_img = create_palette_image(
        palette
    )

    indexed = img.quantize(
        palette=palette_img,
        dither=Image.Dither.FLOYDSTEINBERG
    )

    pixels = indexed.load()
    rows = []

    for y in range(h):
        row = []

        for x in range(w):
            value = pixels[x, y]

            row.append(
                CC_HEX_CHARS[
                    value & 0x0F
                ]
            )

        rows.append(
            "".join(row)
        )

    return {
        "w": w,
        "h": h,
        "rows": rows,
        "palette": [
            [r, g, b]
            for r, g, b in palette
        ],
    }, None


def push_video_payload(
    frame_id,
    payload
):
    global VIDEO_PALETTE
    global VIDEO_PALETTE_FRAME

    if not payload:
        return

    with VIDEO_LOCK:
        current = VIDEO_FRAME[
            "frame"
        ]

        if current is None:
            VIDEO_FRAME["frame"] = frame_id
            VIDEO_FRAME["raw"] = bytes(
                payload
            )
            VIDEO_FRAME[
                "updated_at"
            ] = time.time()
            VIDEO_FRAME[
                "error"
            ] = None

            VIDEO_CACHE.clear()

            VIDEO_PALETTE = None
            VIDEO_PALETTE_FRAME = -1

            return

        if frame_id == current:
            VIDEO_FRAME["raw"] = (
                VIDEO_FRAME["raw"]
                + payload
            )

            VIDEO_FRAME[
                "updated_at"
            ] = time.time()

            return

        VIDEO_FRAME["frame"] = frame_id
        VIDEO_FRAME["raw"] = bytes(
            payload
        )
        VIDEO_FRAME[
            "updated_at"
        ] = time.time()
        VIDEO_FRAME[
            "error"
        ] = None

        VIDEO_CACHE.clear()


def find_free_port(preferred_ports):
    for port in preferred_ports:
        sock = socket.socket(
            socket.AF_INET,
            socket.SOCK_DGRAM
        )

        sock.setsockopt(
            socket.SOL_SOCKET,
            socket.SO_REUSEADDR,
            1
        )

        try:
            sock.bind(
                (UDP_IP, port)
            )

            return port

        except OSError:
            continue

        finally:
            sock.close()

    raise RuntimeError(
        "No free UDP port found in the preferred range"
    )


def verify_udp_bindable(port):
    sock = socket.socket(
        socket.AF_INET,
        socket.SOCK_DGRAM
    )

    sock.setsockopt(
        socket.SOL_SOCKET,
        socket.SO_REUSEADDR,
        1
    )

    try:
        sock.bind(
            (UDP_IP, port)
        )

    except OSError as exc:
        raise RuntimeError(
            f"Cannot bind UDP {port}. "
            "Ensure no other process is using this port."
        ) from exc

    finally:
        sock.close()


def build_test_packet(
    stream_name="Stream2",
    frame=42,
    channels=2
):
    stream = stream_name.encode(
        "ascii"
    ).ljust(
        16,
        b"\0"
    )

    if channels == 1:
        sample_payload = struct.pack(
            "<8h",
            0,
            32767,
            -32768,
            1,
            -1,
            12345,
            -12345,
            64
        )

    else:
        sample_payload = struct.pack(
            "<12h",
            10000,
            -10000,
            20000,
            -20000,
            30000,
            -30000,
            40000,
            -40000,
            5000,
            -5000,
            15000,
            -15000
        )

    packet = (
        b"VBAN"
        + bytes([
            0x03,
            0x00,
            max(0, channels - 1),
            0x01,
        ])
        + stream
        + struct.pack(
            "<I",
            frame
        )
        + sample_payload
    )

    return packet


class BridgeHTTPRequestHandler(
    BaseHTTPRequestHandler
):
    def log_message(self, *args):
        return

    def do_GET(self):
        parsed = urlparse(
            self.path
        )

        qs = parse_qs(
            parsed.query
        )

        if parsed.path == "/health":
            with VIDEO_LOCK:
                video_status = {
                    "stream": VIDEO_STREAM,
                    "frame": VIDEO_FRAME[
                        "frame"
                    ],
                    "bytes": len(
                        VIDEO_FRAME["raw"]
                    ),
                    "updated_at":
                        VIDEO_FRAME[
                            "updated_at"
                        ],
                    "error":
                        VIDEO_FRAME["error"],
                }

            stream_names = (
                set(PCM_STREAMS.keys())
                | set(DFPWM_STREAMS.keys())
            )

            streams = {}

            for name in stream_names:
                channels = AUDIO_CHANNELS.get(
                    name,
                    1
                )

                streams[name] = {
                    "channels": channels,
                    "pcm_samples": {
                        str(channel): len(
                            PCM_STREAMS.get(
                                name,
                                {}
                            ).get(
                                channel,
                                []
                            )
                        )
                        for channel in range(
                            channels
                        )
                    },
                    "dfpwm_bytes": {
                        str(channel): len(
                            DFPWM_STREAMS.get(
                                name,
                                {}
                            ).get(
                                channel,
                                []
                            )
                        )
                        for channel in range(
                            channels
                        )
                    },
                }

            payload = {
                "streams": streams,
                "video": video_status,
            }

            body = json.dumps(
                payload
            ).encode("utf-8")

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "application/json"
            )
            self.send_header(
                "Content-Length",
                str(len(body))
            )
            self.end_headers()

            self.wfile.write(body)

            return

        if parsed.path == "/audio_info":
            stream_name = qs.get(
                "stream",
                ["Stream2"]
            )[0]

            channels = AUDIO_CHANNELS.get(
                stream_name,
                1
            )

            body = json.dumps({
                "ok": True,
                "stream": stream_name,
                "channels": channels,
            }).encode("utf-8")

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "application/json"
            )
            self.send_header(
                "Content-Length",
                str(len(body))
            )
            self.end_headers()

            self.wfile.write(body)

            return

        if parsed.path == "/audio":
            stream_name = qs.get(
                "stream",
                ["Stream2"]
            )[0]

            channel = int(
                qs.get(
                    "channel",
                    ["0"]
                )[0]
            )

            max_samples = int(
                qs.get(
                    "max",
                    ["4096"]
                )[0]
            )

            samples = pop_samples(
                stream_name,
                channel,
                max_samples
            )

            body = ",".join(
                str(value)
                for value in samples
            ).encode(
                "utf-8"
            )

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "text/plain; charset=utf-8"
            )
            self.send_header(
                "Content-Length",
                str(len(body))
            )
            self.end_headers()

            self.wfile.write(body)

            return

        if parsed.path == "/dfpwm":
            stream_name = qs.get(
                "stream",
                ["Stream2"]
            )[0]

            channel = int(
                qs.get(
                    "channel",
                    ["0"]
                )[0]
            )

            max_bytes = int(
                qs.get(
                    "max",
                    ["2048"]
                )[0]
            )

            body = pop_dfpwm(
                stream_name,
                channel,
                max_bytes
            )

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "application/octet-stream"
            )
            self.send_header(
                "Content-Length",
                str(len(body))
            )
            self.end_headers()

            self.wfile.write(body)

            return

        if parsed.path == "/video":
            requested_stream = qs.get(
                "stream",
                [VIDEO_STREAM]
            )[0]

            max_w = int(
                qs.get(
                    "w",
                    ["64"]
                )[0]
            )

            max_h = int(
                qs.get(
                    "h",
                    ["32"]
                )[0]
            )

            if requested_stream != VIDEO_STREAM:
                body = json.dumps({
                    "ok": False,
                    "error": (
                        f"Unknown video stream "
                        f"'{requested_stream}'"
                    ),
                }).encode(
                    "utf-8"
                )

                self.send_response(404)
                self.send_header(
                    "Content-Type",
                    "application/json"
                )
                self.send_header(
                    "Content-Length",
                    str(len(body))
                )
                self.end_headers()

                self.wfile.write(body)

                return

            with VIDEO_LOCK:
                frame_id = VIDEO_FRAME[
                    "frame"
                ]

                raw = VIDEO_FRAME[
                    "raw"
                ]

                updated_at = VIDEO_FRAME[
                    "updated_at"
                ]

                cached = VIDEO_CACHE.get(
                    (
                        frame_id,
                        max_w,
                        max_h
                    )
                )

            if cached is None:
                rendered, err = (
                    render_video_rows(
                        raw,
                        max_w,
                        max_h
                    )
                )

                if rendered is not None:
                    with VIDEO_LOCK:
                        if (
                            VIDEO_FRAME[
                                "frame"
                            ]
                            == frame_id
                        ):
                            VIDEO_CACHE[
                                (
                                    frame_id,
                                    max_w,
                                    max_h
                                )
                            ] = rendered

                else:
                    with VIDEO_LOCK:
                        VIDEO_FRAME[
                            "error"
                        ] = err

            else:
                rendered = cached
                err = None

            if (
                cached is None
                and rendered is None
            ):
                body = json.dumps({
                    "ok": False,
                    "stream": VIDEO_STREAM,
                    "frame": frame_id,
                    "updated_at": updated_at,
                    "error": err,
                }).encode(
                    "utf-8"
                )

            else:
                payload = {
                    "ok": True,
                    "stream": VIDEO_STREAM,
                    "frame": frame_id,
                    "updated_at": updated_at,
                    "w": rendered["w"],
                    "h": rendered["h"],
                    "rows": rendered["rows"],
                    "palette": rendered[
                        "palette"
                    ],
                }

                body = json.dumps(
                    payload
                ).encode(
                    "utf-8"
                )

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "application/json"
            )
            self.send_header(
                "Content-Length",
                str(len(body))
            )
            self.end_headers()

            self.wfile.write(body)

            return

        self.send_response(404)
        self.end_headers()


def udp_worker(port):
    sock = socket.socket(
        socket.AF_INET,
        socket.SOCK_DGRAM
    )

    sock.setsockopt(
        socket.SOL_SOCKET,
        socket.SO_REUSEADDR,
        1
    )

    sock.bind(
        (UDP_IP, port)
    )

    sock.settimeout(0.5)

    print(
        f"Listening for VBAN on UDP "
        f"{UDP_IP}:{port}"
    )

    last_frames = {}
    lost_packets = 0
    packet_count = 0
    start = time.monotonic()

    while True:
        try:
            data, _addr = sock.recvfrom(
                65535
            )

        except socket.timeout:
            continue

        pkt = parse_vban(data)

        if pkt is None:
            continue

        if (
            pkt["fmt"] != "pcm16le"
            or pkt["rate"] is None
        ):
            continue

        packet_count += 1

        stream_name = pkt[
            "stream"
        ]

        frame = pkt[
            "frame"
        ]

        last_frame = last_frames.get(
            stream_name
        )

        if last_frame is not None:
            delta = (
                frame - last_frame
            ) & 0xFFFFFFFF

            if delta > 1:
                lost_packets += (
                    delta - 1
                )

        last_frames[
            stream_name
        ] = frame

        channel_samples = (
            split_pcm16_channels(
                pkt["payload"],
                pkt["channels"]
            )
        )

        if not channel_samples:
            continue

        queue_audio_channels(
            stream_name,
            channel_samples
        )

        elapsed = (
            time.monotonic()
            - start
        )

        if elapsed > 1.0:
            #print(
            #    f"packets/sec≈"
            #    f"{packet_count / elapsed:.2f} "
            #    f"| lost={lost_packets}"
            #)
            pass

            packet_count = 0
            lost_packets = 0
            start = time.monotonic()


def udp_video_worker(port):
    sock = socket.socket(
        socket.AF_INET,
        socket.SOCK_DGRAM
    )

    sock.setsockopt(
        socket.SOL_SOCKET,
        socket.SO_REUSEADDR,
        1
    )

    sock.bind(
        (UDP_IP, port)
    )

    sock.settimeout(0.5)

    print(
        f"Listening for VBAN video on UDP "
        f"{UDP_IP}:{port} "
        f"stream={VIDEO_STREAM}"
    )

    packet_count = 0
    start = time.monotonic()

    while True:
        try:
            data, _addr = sock.recvfrom(
                65535
            )

        except socket.timeout:
            continue

        pkt = parse_vban(data)

        if pkt is None:
            continue

        if pkt["stream"] != VIDEO_STREAM:
            continue

        if not pkt["payload"]:
            continue

        packet_count += 1

        push_video_payload(
            pkt["frame"],
            pkt["payload"]
        )

        elapsed = (
            time.monotonic()
            - start
        )

        if elapsed > 1.0:
            #print(
            #    f"video packets/sec≈"
            #    f"{packet_count / elapsed:.2f}"
            #)

            packet_count = 0
            start = time.monotonic()


def http_worker(port):
    server = ThreadingHTTPServer(
        (
            HTTP_IP,
            port
        ),
        BridgeHTTPRequestHandler
    )

    print(
        f"HTTP bridge running on "
        f"http://{HTTP_IP}:{port}"
    )

    server.serve_forever()


def self_test():
    udp_port = find_free_port(
        DEFAULT_PORTS
    )

    udp_thread = threading.Thread(
        target=udp_worker,
        args=(udp_port,),
        daemon=True
    )

    udp_thread.start()

    http_thread = threading.Thread(
        target=http_worker,
        args=(HTTP_PORT,),
        daemon=True
    )

    http_thread.start()

    time.sleep(0.5)

    sender = socket.socket(
        socket.AF_INET,
        socket.SOCK_DGRAM
    )

    sender.sendto(
        build_test_packet(
            channels=2
        ),
        (
            "127.0.0.1",
            udp_port
        )
    )

    sender.close()

    deadline = (
        time.monotonic()
        + 5.0
    )

    while (
        time.monotonic()
        < deadline
    ):
        channels = AUDIO_CHANNELS.get(
            "Stream2"
        )

        if channels == 2:
            left = PCM_STREAMS[
                "Stream2"
            ].get(0)

            right = PCM_STREAMS[
                "Stream2"
            ].get(1)

            if (
                left
                and right
                and len(left) >= 6
                and len(right) >= 6
            ):
                break

        time.sleep(0.05)

    left = pop_samples(
        "Stream2",
        0,
        6
    )

    right = pop_samples(
        "Stream2",
        1,
        6
    )

    assert AUDIO_CHANNELS[
        "Stream2"
    ] == 2

    assert left == [
        39,
        78,
        117,
        127,
        19,
        58
    ], left

    assert right == [
        -40,
        -79,
        -118,
        -128,
        -20,
        -59
    ], right

    left_dfpwm = pop_dfpwm(
        "Stream2",
        0,
        64
    )

    right_dfpwm = pop_dfpwm(
        "Stream2",
        1,
        64
    )

    assert left_dfpwm
    assert right_dfpwm

    assert left_dfpwm != right_dfpwm

    print(
        f"self-test OK on UDP "
        f"{udp_port} and HTTP "
        f"{HTTP_PORT}"
    )

    return (
        udp_port,
        HTTP_PORT
    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_UDP_PORT,
        help="UDP port to listen on"
    )

    parser.add_argument(
        "--video-port",
        type=int,
        default=DEFAULT_VIDEO_UDP_PORT,
        help="UDP port for VBAN video"
    )

    parser.add_argument(
        "--video-stream",
        type=str,
        default=DEFAULT_VIDEO_STREAM,
        help="VBAN video stream name"
    )

    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run a short local packet test and exit"
    )

    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    global VIDEO_STREAM

    VIDEO_STREAM = args.video_stream

    udp_port = args.port
    video_port = args.video_port

    verify_udp_bindable(
        udp_port
    )

    if video_port != udp_port:
        verify_udp_bindable(
            video_port
        )

    udp_thread = threading.Thread(
        target=udp_worker,
        args=(udp_port,),
        daemon=True
    )

    udp_thread.start()

    if video_port == udp_port:
        print(
            "Video port equals audio port; "
            "VBAN video must use a dedicated UDP port."
        )

        print(
            "Set --video-port to a different port "
            "(example: 6982)."
        )

    else:
        video_thread = threading.Thread(
            target=udp_video_worker,
            args=(video_port,),
            daemon=True
        )

        video_thread.start()

    http_thread = threading.Thread(
        target=http_worker,
        args=(HTTP_PORT,),
        daemon=True
    )

    http_thread.start()

    print(
        f"Bridge ready: audio UDP {udp_port}, "
        f"video UDP {video_port}, "
        f"HTTP {HTTP_PORT}"
    )

    while True:
        time.sleep(1)


if __name__ == "__main__":
    main()
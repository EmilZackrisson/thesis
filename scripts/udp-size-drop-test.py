import socket
import time
import threading
import logging

UDP_IP = "10.200.200.1"
UDP_PORT = 30002

COUNT_PER_SIZE = 10
START_SIZE = 1000
END_SIZE = 1500
INCREMENT_SIZE = 5
DELAY_S = 0.01
RESPONSE_TIMEOUT = 0.05  # seconds to wait for a response for each packet

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
logging.info("UDP target IP: %s", UDP_IP)
logging.info("UDP target port: %s", UDP_PORT)

def build_payload_counter(counter: int, cur_size: int, counter_len: int = 4) -> bytearray:
    if cur_size < counter_len:
        raise ValueError(f"cur_size must be >= {counter_len}")
    return bytearray(counter.to_bytes(counter_len, "big") + b'x' * (cur_size - counter_len))

sock = socket.socket(socket.AF_INET, # Internet
                     socket.SOCK_DGRAM) # UDP

# Bind so we can receive responses on the same port
sock.bind(("", 0))
local_port = sock.getsockname()[1]
logging.info("Bound local socket on port %d", local_port)
sock.settimeout(1.0)

# Shared state for received counters
received_counters = set()
rc_lock = threading.Lock()
stop_event = threading.Event()

def listener():
    while not stop_event.is_set():
        try:
            data, addr = sock.recvfrom(65535)
        except socket.timeout:
            continue
        except OSError:
            break
        if not data:
            continue
        if len(data) < 4:
            continue
        counter = int.from_bytes(data[:4], "big")
        with rc_lock:
            received_counters.add(counter)
        #logging.info("Received response from %s:%d counter=%d", addr[0], addr[1], counter)

listener_thread = threading.Thread(target=listener, daemon=True)
listener_thread.start()

cur_size = START_SIZE
i = 0
try:
    while cur_size <= END_SIZE:

        for _ in range(COUNT_PER_SIZE):

            # Build a bytearray, starting with a 4-byte counter and the rest filled with 'x' of size cur_size
            data = build_payload_counter(i, cur_size)
            sock.sendto(data, (UDP_IP, UDP_PORT))

            # Wait briefly for a response containing the counter byte
            deadline = time.time() + RESPONSE_TIMEOUT
            seen = False
            while time.time() < deadline:
                with rc_lock:
                    if i in received_counters:
                        seen = True
                        # remove to keep the set small and avoid reused matches
                        received_counters.discard(i)
                        break
                time.sleep(0.005)

            if not seen:
                logging.warning("No response for counter %d size %d", i, cur_size)
            #else:
            #    logging.info("Got response for counter %d", i)

            i += 1
            time.sleep(DELAY_S)

        cur_size = cur_size + INCREMENT_SIZE
        
finally:
    stop_event.set()
    try:
        listener_thread.join(timeout=1.0)
    except RuntimeError:
        pass
    sock.close()
import cv2, numpy as np, time

# ---- params (tweak if needed) ----
GX, GY = 16, 16        # tiles across/down
THRESH = 15            # brightness delta threshold (0..255)
CAM = 0                # camera index (use your HDMI capture card index here)

cap = cv2.VideoCapture(CAM)
cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)    # try to reduce lag (may be ignored)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
cap.set(cv2.CAP_PROP_FPS, 60)

ok, prev_bgr = cap.read()
if not ok:
    raise SystemExit("No camera frames. Check CAM index / device.")
prev = cv2.cvtColor(prev_bgr, cv2.COLOR_BGR2GRAY)
h, w = prev.shape
tw, th = w // GX, h // GY

def draw_grid(img):
    for x in range(0, w, tw):
        cv2.line(img, (x, 0), (x, h), (60,60,60), 1)
    for y in range(0, h, th):
        cv2.line(img, (0, y), (w, y), (60,60,60), 1)

ema = None
last_frame_time = None   # <-- new: store time of previous frame

while True:
    capture_time = time.time()  # time before grabbing a frame
    ok, bgr = cap.read()
    if not ok: break

    # ---- Frame time measurement ----
    if last_frame_time is not None:
        delivered_frame_time_ms = (capture_time - last_frame_time) * 1000.0
    else:
        delivered_frame_time_ms = 0.0
    last_frame_time = capture_time

    # ---- Processing ----
    t0 = time.perf_counter()
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)

    for ty in range(GY):
        y0, y1 = ty*th, (ty+1)*th
        for tx in range(GX):
            x0, x1 = tx*tw, (tx+1)*tw
            d = abs(float(np.mean(gray[y0:y1, x0:x1])) - float(np.mean(prev[y0:y1, x0:x1])))
            if d > THRESH:
                cv2.rectangle(bgr, (x0, y0), (x1-1, y1-1), (0,0,255), 2)

    draw_grid(bgr)

    # ---- Latency metrics ----
    processing_latency_ms = (time.perf_counter() - t0) * 1000.0

    # old E2E (processing + time after capture)
    end_to_end_latency_ms_raw = (time.time() - capture_time) * 1000.0
    # new E2E = frame delivery + everything else
    estimated_total_latency_ms = delivered_frame_time_ms + end_to_end_latency_ms_raw

    # ---- FPS (processing-based) ----
    fps = 1.0 / max(1e-6, (time.perf_counter() - t0))
    ema = fps if ema is None else 0.9*ema + 0.1*fps

    # ---- Overlay metrics ----
    cv2.putText(bgr, f"Proc Latency: {processing_latency_ms:.2f} ms", (10,50),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0,255,0), 2, cv2.LINE_AA)
    cv2.putText(bgr, f"Frame Time: {delivered_frame_time_ms:.2f} ms", (10,76),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255,0,0), 2, cv2.LINE_AA)
    cv2.putText(bgr, f"End-to-End (raw): {end_to_end_latency_ms_raw:.2f} ms", (10,102),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0,255,255), 2, cv2.LINE_AA)
    cv2.putText(bgr, f"Est. Total Latency: {estimated_total_latency_ms:.2f} ms", (10,128),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0,0,255), 2, cv2.LINE_AA)

    # ---- Info Note ----
    note = "Note: Total Latency = Frame Time + Raw E2E (sensor + driver + processing)"
    cv2.putText(bgr, note, (10, h - 20),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (180,180,180), 1, cv2.LINE_AA)

    cv2.imshow("Motion Tiles", bgr)
    prev = gray

    k = cv2.waitKey(1) & 0xFF
    if k == 27: break                   # ESC to quit
    elif k in (ord('+'), ord('=')): THRESH = min(255, THRESH+1)
    elif k in (ord('-'), ord('_')): THRESH = max(0, THRESH-1)

cap.release()
cv2.destroyAllWindows()

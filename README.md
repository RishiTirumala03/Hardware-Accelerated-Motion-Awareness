# Real-Time Tile-Based Motion Detection Accelerator (FPGA)

## Project Overview
This project implements a **real-time, tile-based motion detection pipeline** on FPGA to remove frame buffering delays found in traditional CPU-based image processing. By processing pixels as they arrive, the design achieves **sub-frame latency** and reduces end-to-end delay by approximately **35 ms** compared to a software pipeline.  

The system outputs motion vectors tile-by-tile in hardware and overlays the result directly on an HDMI output. This makes it highly suitable for **gesture recognition**, **autonomous perception**, and other **embedded vision applications**.

A software-based demo was built to compare the hardware-based version and the software-based version. The software-based version was entirely vibe-coded. It is by no means robust.
---

## Core Concept
- **Input:** Live 720p HDMI video stream  
- **Processing:** Real-time per-tile brightness accumulation and adaptive binary thresholding to detect motion  
- **Output:** Tile-level motion overlay rendered in real time with minimal latency

---

## IP Cores Used (from [Digilent](https://digilent.com))
- `DVI2RGB` — HDMI input interface  
- `Clocking Wizard` — pixel and fabric clock generation  
- `RGB2DVI` — HDMI output interface

---

## Custom Hardware Modules
- `bin_thresh.v` — Adaptive binary thresholding using moving average for robust noise suppression  
- `vecgen.v` — Tile-based brightness motion detection engine (1-bit output per tile)  
- Tile grid overlay logic — Real-time visualization of detected motion  
- Latency instrumentation — For measuring hardware vs software processing times

---

## Performance Highlights
- Resolution: 1280 × 720 (720p) @ 60 FPS  
- End-to-end latency reduction: **~35 ms** compared to CPU implementation  
- Adaptive noise filtering with minimal resource usage  
- Fully pipelined architecture suitable for ASIC/SoC dataflow integration

---

## Development Environment
- **FPGA Board:** Zybo Z7  
- **Toolchain:** Vivado 2025 
- **Languages:** Verilog HDL  
- **OS / Host:** Windows 11, Python + OpenCV for software reference pipeline

---

##  Future Work
- Implement centroid tracking and direction vectors for more advanced motion analysis  
- Extend AXI interface for easier SoC integration  
- Add gesture classification layers for real-time interaction systems

---

##  Author
**Rishi Tirumala**  
Electrical Engineering & Computer Science  
University of California, Irvine

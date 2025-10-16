`timescale 1ns / 1ps
// vecgen.v - Per-tile brightness motion detector (1-bit output per tile, fixed version)

module vecgen #(
  parameter integer H_ACTIVE  = 1280,
  parameter integer V_ACTIVE  = 720,
  parameter integer GX        = 16,       // tiles across
  parameter integer GY        = 16,       // tiles down
  parameter integer THRESHOLD = 32'd10000 // realistic threshold for 720p tiles
)(
  input  wire        pclk,
  input  wire        rst,

  // video input
  input  wire [23:0] s_pData,
  input  wire        s_pVDE,
  input  wire        s_pHSync,
  input  wire        s_pVSync,

  // per-tile motion output
  output reg         vec_we,            // pulses high for 1 clk when tile result valid
  output reg  [7:0]  vec_addr,          // {ty, tx} index of tile (0..255)
  output reg         motion_detected    // 1 = motion, 0 = none
);

  // ---------- geometry / counters ----------
  localparam integer N   = GX * GY;
  localparam integer TW  = H_ACTIVE / GX;
  localparam integer TH  = V_ACTIVE / GY;

  localparam AWX   = $clog2(H_ACTIVE);
  localparam AWY   = $clog2(V_ACTIVE);
  localparam AW_TX = $clog2(GX);
  localparam AW_TY = $clog2(GY);
  localparam AW_TW = $clog2(TW);
  localparam AW_TH = $clog2(TH);

  // ---------- pixel/line counters ----------
  reg [AWX-1:0] x;
  reg [AWY-1:0] y;
  reg vde_d;
  wire vde_rise = ~vde_d &  s_pVDE;
  wire vde_fall =  vde_d & ~s_pVDE;
  always @(posedge pclk) vde_d <= s_pVDE;

  always @(posedge pclk) begin
    if (rst) begin
      x <= 0; y <= 0;
    end else begin
      if (s_pVDE)
        x <= (x == H_ACTIVE-1) ? 0 : (x + 1'b1);
      else
        x <= 0;

      if (vde_fall)
        y <= (y == V_ACTIVE-1) ? 0 : (y + 1'b1);
    end
  end

  // ---------- tile-local counters ----------
  reg [AW_TW-1:0] sx; // pixel idx within tile
  reg [AW_TX-1:0] tx; // tile x
  reg [AW_TH-1:0] ly; // line idx within tile
  reg [AW_TY-1:0] ty; // tile y

  always @(posedge pclk) begin
    if (rst) begin
      sx <= 0; tx <= 0; ly <= 0; ty <= 0;
    end else begin
      if (s_pVDE) begin
        sx <= (sx == TW - 1) ? 0 : sx + 1'b1;
        if (sx == TW - 1) tx <= (tx == GX - 1) ? 0 : tx + 1'b1;
      end else begin
        sx <= 0;
        tx <= 0;
      end

      if (vde_fall) begin
        ly <= (ly == TH - 1) ? 0 : ly + 1'b1;
        if (ly == TH - 1) ty <= (ty == GY - 1) ? 0 : ty + 1'b1;
      end
    end
  end

  wire [7:0] cur_idx = {ty, tx};
  wire end_of_tile = s_pVDE && (sx == TW - 1) && (ly == TH - 1);

  // ---------- luma conversion to reduce noise ----------
  wire [15:0] y_acc = s_pData[23:16]*8'd77 + s_pData[15:8]*8'd150 + s_pData[7:0]*8'd29;
  wire [7:0]  y8    = y_acc[15:8];

  // ---------- per-tile brightness accumulators ----------
  reg [31:0] tile_acc        [0:N-1];
  reg [31:0] prev_brightness [0:N-1];

  reg [31:0] acc_next;
  reg first_frame;
  integer i;

  always @(posedge pclk) begin
    if (rst) begin
      vec_we          <= 1'b0;
      motion_detected <= 1'b0;
      vec_addr        <= 8'd0;
      first_frame     <= 1'b1;
      acc_next        <= 32'd0;
      for (i = 0; i < N; i = i + 1) begin
        tile_acc[i]        <= 32'd0;
        prev_brightness[i] <= 32'd0;
      end
    end else begin
      vec_we <= 1'b0;

      // accumulate pixel brightness
      if (s_pVDE) begin
        tile_acc[cur_idx] <= tile_acc[cur_idx] + y8;
      end

      if (end_of_tile) begin
        acc_next <= tile_acc[cur_idx] + y8;
        vec_addr <= cur_idx;
        vec_we   <= 1'b1;

        if (!first_frame) begin
          if (acc_next > prev_brightness[cur_idx] + THRESHOLD ||
              acc_next + THRESHOLD < prev_brightness[cur_idx])
            motion_detected <= 1'b1;
          else
            motion_detected <= 1'b0;
        end else begin
          motion_detected <= 1'b0;
        end

        prev_brightness[cur_idx] <= acc_next;
        tile_acc[cur_idx]        <= 32'd0;
      end

      // mark end of first frame
      if (vde_fall && (y == V_ACTIVE - 1)) begin
        first_frame <= 1'b0;
      end
    end
  end

endmodule

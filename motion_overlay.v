`timescale 1ns / 1ps
// motion_overlay.v - red box overlay with tile counter logic EXACTLY matching vecgen

module motion_overlay #(
  parameter integer H_ACTIVE   = 1280,
  parameter integer V_ACTIVE   = 720,
  parameter integer GX         = 16,
  parameter integer GY         = 16,
  parameter [23:0] BOX_RGB     = 24'hFF0000
)(
  input  wire        pclk,
  input  wire        rst,

  input  wire [23:0] s_pData,
  input  wire        s_pVDE,
  input  wire        s_pHSync,
  input  wire        s_pVSync,

  input  wire        vec_we,
  input  wire [7:0]  vec_addr,
  input  wire        motion_detected,

  output reg  [23:0] m_pData,
  output reg         m_pVDE,
  output reg         m_pHSync,
  output reg         m_pVSync
);

  localparam integer TW = H_ACTIVE / GX;
  localparam integer TH = V_ACTIVE / GY;

  localparam AWX = $clog2(H_ACTIVE);
  localparam AWY = $clog2(V_ACTIVE);
  localparam LWX = $clog2(TW);
  localparam LWY = $clog2(TH);

  // pixel counters
  reg [AWX-1:0] x;
  reg [AWY-1:0] y;
  reg vde_d;
  wire vde_fall = vde_d & ~s_pVDE;
  always @(posedge pclk) vde_d <= s_pVDE;

  always @(posedge pclk) begin
    if (rst) begin
      x <= 0;
      y <= 0;
    end else begin
      if (s_pVDE) begin
        x <= (x == H_ACTIVE - 1) ? 0 : x + 1'b1;
      end else begin
        x <= 0;
      end
      if (vde_fall) begin
        y <= (y == V_ACTIVE - 1) ? 0 : y + 1'b1;
      end
    end
  end

  // tile counters (now match vecgen 1:1)
  reg [LWX-1:0] xl;
  reg [LWY-1:0] yl;
  reg [3:0]     tx;
  reg [3:0]     ty;

  always @(posedge pclk) begin
    if (rst) begin
      xl <= 0; yl <= 0; tx <= 0; ty <= 0;
    end else begin
      if (s_pVDE) begin
        if (xl == TW - 1) begin
          xl <= 0;
          if (tx == GX - 1)
            tx <= 0;
          else
            tx <= tx + 1'b1;
        end else begin
          xl <= xl + 1'b1;
        end
      end else begin
        // 🔥 MATCH VECGEN: reset horizontal tile counter on blanking
        xl <= 0;
        tx <= 0;
      end

      if (vde_fall) begin
        if (yl == TH - 1) begin
          yl <= 0;
          if (ty == GY - 1)
            ty <= 0;
          else
            ty <= ty + 1'b1;
        end else begin
          yl <= yl + 1'b1;
        end
      end
    end
  end

  wire [7:0] tid_now = {ty, tx};

  // motion memory
  reg motion_mem [0:255];
  integer i;
  always @(posedge pclk) begin
    if (rst) begin
      for (i = 0; i < 256; i = i + 1)
        motion_mem[i] <= 1'b0;
    end else if (vec_we) begin
      motion_mem[vec_addr] <= motion_detected;
    end
  end

  reg motion_now;
  always @(posedge pclk) begin
    motion_now <= motion_mem[tid_now];
  end

  // draw red box
  wire on_box = motion_now && (
                  (xl == 0) || (xl == TW - 1) ||
                  (yl == 0) || (yl == TH - 1)
                );

  // output mux
  always @(posedge pclk) begin
    if (rst) begin
      m_pData  <= 24'd0;
      m_pVDE   <= 1'b0;
      m_pHSync <= 1'b0;
      m_pVSync <= 1'b0;
    end else begin
      m_pVDE   <= s_pVDE;
      m_pHSync <= s_pHSync;
      m_pVSync <= s_pVSync;

      if (s_pVDE) begin
        m_pData <= on_box ? BOX_RGB : s_pData;
      end else begin
        m_pData <= 24'd0;
      end
    end
  end

endmodule

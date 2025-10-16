`timescale 1ns / 1ps
// sobel_xy.v - streaming 3×3 Sobel (|Gx| + |Gy|), grayscale out on RGB
// sobel_xy_inferred.v - streaming 3×3 Sobel (|Gx|+|Gy|), no XPM
module sobel #(
  parameter integer H_ACTIVE = 1280   // 1920 for 1080p
)(
  input  wire        pclk,
  input  wire        rst,            // active-HIGH, sync to pclk

  input  wire [23:0] s_pData,
  input  wire        s_pVDE,
  input  wire        s_pHSync,
  input  wire        s_pVSync,

  output reg  [23:0] m_pData,
  output reg         m_pVDE,
  output reg         m_pHSync,
  output reg         m_pVSync
);
  // ---------- helpers ----------
  function [7:0] rgb2y;
    input [23:0] rgb; reg [15:0] acc;
    begin
      acc   = rgb[23:16]*8'd77 + rgb[15:8]*8'd150 + rgb[7:0]*8'd29;
      rgb2y = acc[15:8];
    end
  endfunction
  function [11:0] abs12; input signed [11:0] x; begin abs12 = x[11] ? -x : x; end endfunction

  localparam integer AW = $clog2(H_ACTIVE);

  // control alignment (three stages to match data)
  reg vde_d0, vde_d1, vde_d2;
  reg hs_d0,  hs_d1,  hs_d2;
  reg vs_d0,  vs_d1,  vs_d2;

  // column counter inside active video
  reg [AW-1:0] x;
  wire sol = (~vde_d0) & s_pVDE;     // start of active line
  wire eol = vde_d0 & ~s_pVDE;       // end of active line

  // grayscale current pixel and a one-cycle delay to match BRAM read
  wire [7:0] y_cur_w = rgb2y(s_pData);
  reg  [7:0] y_cur_d;

  // inferred BRAM line buffers (A & B) 
  // We read both memories every cycle at address x (combinational -> registered),
  // and write the *current* line into whichever RAM is acting as "row-2".
  // At end-of-line we swap roles via 'sel'.
  (* ram_style = "block" *) reg [7:0] ram_a [0:H_ACTIVE-1];
  (* ram_style = "block" *) reg [7:0] ram_b [0:H_ACTIVE-1];
  reg [7:0] dout_a, dout_b;

  reg       sel;          // 0: row-1=A,row-2=B ; 1: row-1=B,row-2=A
  wire      we_a = s_pVDE &  sel;    // write current line into row-2 RAM
  wire      we_b = s_pVDE & ~sel;

  // Read/Write (READ_FIRST behavior via registered read, then write)
  always @(posedge pclk) begin
    // registered reads (1-cycle latency)
    dout_a <= ram_a[x];
    dout_b <= ram_b[x];

    // writes
    if (we_a) ram_a[x] <= y_cur_w;
    if (we_b) ram_b[x] <= y_cur_w;
  end

  wire [7:0] rowm1_rd = sel ? dout_b : dout_a;  // previous line
  wire [7:0] rowm2_rd = sel ? dout_a : dout_b;  // two lines up

  // 3×3 window shift regs
  reg [7:0] t0,t1,t2, m0,m1,m2, b0,b1,b2;

  // Sobel math
  reg  signed [11:0] gx, gy;
  wire [11:0] agx = abs12(gx), agy = abs12(gy);
  wire [12:0] mag_w = agx + agy;
  wire [7:0]  mag8  = (|mag_w[12:8]) ? 8'hFF : mag_w[7:0];

  // window-valid flags
  reg have2cols;
  reg [1:0] rows_seen;   // becomes 2 after two lines have been stored
  wire have2rows = rows_seen[1];

  //pipeline
  always @(posedge pclk) begin
    if (rst) begin
      vde_d0<=0; vde_d1<=0; vde_d2<=0;
      hs_d0<=0;  hs_d1<=0;  hs_d2<=0;
      vs_d0<=0;  vs_d1<=0;  vs_d2<=0;

      x <= {AW{1'b0}};
      y_cur_d <= 8'd0;
      {t0,t1,t2,m0,m1,m2,b0,b1,b2} <= {9{8'd0}};
      have2cols <= 1'b0;
      rows_seen <= 2'd0;
      sel <= 1'b0;

      gx <= 12'sd0; gy <= 12'sd0;
      m_pData <= 24'd0; m_pVDE <= 1'b0; m_pHSync <= 1'b0; m_pVSync <= 1'b0;
    end else begin
      // control delays (3 stages)
      vde_d0 <= s_pVDE;  vde_d1 <= vde_d0;  vde_d2 <= vde_d1;
      hs_d0  <= s_pHSync; hs_d1 <= hs_d0;   hs_d2  <= hs_d1;
      vs_d0  <= s_pVSync; vs_d1 <= vs_d0;   vs_d2  <= vs_d1;

      // align grayscale with BRAM reads
      y_cur_d <= y_cur_w;

      // x within active line
      if (s_pVDE) begin
        x <= (x == H_ACTIVE-1) ? {AW{1'b0}} : x + 1'b1;
      end

      // start/end of active line
      if (sol) have2cols <= 1'b0;
      if (eol) begin
        sel <= ~sel;                                       // swap row roles
        rows_seen <= (rows_seen == 2'd2) ? 2'd2 : rows_seen + 1'b1;
        have2cols <= 1'b0;
      end

      // build 3×3 window (rowm* valid 1 cycle after address)
      if (s_pVDE) begin
        t0 <= t1;  t1 <= t2;  t2 <= rowm2_rd;      // top row
        m0 <= m1;  m1 <= m2;  m2 <= rowm1_rd;      // middle row
        b0 <= b1;  b1 <= b2;  b2 <= y_cur_d;       // bottom row

        if (!have2cols) have2cols <= (x >= 2);
      end else begin
        {t0,t1,t2,m0,m1,m2,b0,b1,b2} <= {9{8'd0}};
      end

      // Sobel compute when window valid
      if (have2cols && have2rows && vde_d2) begin
        // Gx = (t2 + 2*m2 + b2) - (t0 + 2*m0 + b0)
        gx <= $signed({4'd0,t2}) + $signed({3'd0,m2,1'b0}) + $signed({4'd0,b2})
            - ($signed({4'd0,t0}) + $signed({3'd0,m0,1'b0}) + $signed({4'd0,b0}));

        // Gy = (b0 + 2*b1 + b2) - (t0 + 2*t1 + t2)
        gy <= $signed({4'd0,b0}) + $signed({3'd0,b1,1'b0}) + $signed({4'd0,b2})
            - ($signed({4'd0,t0}) + $signed({3'd0,t1,1'b0}) + $signed({4'd0,t2}));

        m_pData <= {3{mag8}};   // grayscale magnitude replicated on RGB
      end else begin
        gx <= 12'sd0; gy <= 12'sd0;
        m_pData <= 24'd0;       // black on borders/blanking
      end

      // aligned control out
      m_pVDE   <= vde_d2;
      m_pHSync <= hs_d2;
      m_pVSync <= vs_d2;
    end
  end
endmodule

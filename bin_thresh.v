`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/24/2025
// Design Name: 
// Module Name: bin_thresh_ma
// Project Name: Motion Detection Pipeline
// Target Devices: FPGA
// Description: Binary threshold with adaptive moving average, noise suppression,
//              and optional grayscale conversion 
//////////////////////////////////////////////////////////////////////////////////

module bin_thresh #(
  parameter integer USE_LUMA    = 1,   // 1 = use luma, 0 = use raw channel
  parameter integer ALPHA_SHIFT = 6,   // smoothing factor (higher = less noise)
  parameter integer BIAS        = 110,  // brightness offset to detect motion
  parameter integer ERR_FLOOR   = 60   // minimum deviation required to trigger
)(
  input  wire        pclk,
  input  wire        rst,          // active-high, sync to pclk

  // incoming pixel stream
  input  wire [23:0] s_pData,
  input  wire        s_pVDE,
  input  wire        s_pHSync,
  input  wire        s_pVSync,

  // outgoing binary mask
  output reg  [23:0] m_pData,     
  output reg         m_pVDE,
  output reg         m_pHSync,
  output reg         m_pVSync
);

  // Helper functions 
  // Convert RGB to luma (grayscale intensity)
  function [7:0] rgb2y;
    input [23:0] rgb;
    reg [15:0] acc;
    begin
      acc    = rgb[23:16]*8'd77 + rgb[15:8]*8'd150 + rgb[7:0]*8'd29;
      rgb2y  = acc[15:8];
    end
  endfunction

  // Saturation clamp to 8 bits
  function [7:0] sat8;
    input signed [9:0] x;
    begin
      if (x < 0)
        sat8 = 8'd0;
      else if (x > 9'sd255)
        sat8 = 8'd255;
      else
        sat8 = x[7:0];
    end
  endfunction

  // Main pipeline 
  wire [7:0] val8 = USE_LUMA ? rgb2y(s_pData) : s_pData[7:0];

  reg  [7:0] mean8 = 8'd0;

  wire signed [8:0] err = $signed({1'b0,val8}) - $signed({1'b0,mean8});
  wire [7:0] abs_err = err[8] ? -err[7:0] : err[7:0];

  wire signed [9:0] mean_next = $signed({1'b0,mean8}) + (err >>> ALPHA_SHIFT);
  wire signed [9:0] thr_s     = $signed({1'b0,mean8}) + $signed(BIAS);
  wire [7:0]        thr8      = sat8(thr_s);

  // Thresholding
  wire edge_bit = (val8 >= thr8) && (abs_err >= ERR_FLOOR);

  //Output registers
  always @(posedge pclk) begin
    if (rst) begin
      mean8    <= 8'd0;
      m_pData  <= 24'd0;
      m_pVDE   <= 1'b0;
      m_pHSync <= 1'b0;
      m_pVSync <= 1'b0;
    end else begin
      // adaptive moving average
      if (s_pVDE) mean8 <= sat8(mean_next);

      // pass control signals
      m_pVDE   <= s_pVDE;
      m_pHSync <= s_pHSync;
      m_pVSync <= s_pVSync;

      // binary output
      m_pData  <= s_pVDE ? (edge_bit ? 24'hFFFFFF : 24'h000000) : 24'd0;
    end
  end

endmodule

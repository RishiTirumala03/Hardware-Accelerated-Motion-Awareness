`timescale 1ns/1ps

module vecgen_tb_minimal;

  localparam integer H_ACTIVE = 1280;
  localparam integer V_ACTIVE = 720;
  localparam integer GX       = 16;
  localparam integer GY       = 16;

  reg pclk = 0;
  always #5 pclk = ~pclk; // 100 MHz

  reg rst = 1;
  initial begin
    repeat (8) @(posedge pclk);
    rst = 0;
  end

  reg  [23:0] s_pData  = 24'h0;
  reg         s_pVDE   = 0;
  reg         s_pHSync = 1;
  reg         s_pVSync = 1;

  wire        vec_we;
  wire [7:0]  vec_addr;
  wire        motion_detected;

  // DUT instantiation
  vecgen #(
    .H_ACTIVE(H_ACTIVE),
    .V_ACTIVE(V_ACTIVE),
    .GX(GX),
    .GY(GY)
  ) dut (
    .pclk(pclk),
    .rst(rst),
    .s_pData(s_pData),
    .s_pVDE(s_pVDE),
    .s_pHSync(s_pHSync),
    .s_pVSync(s_pVSync),
    .vec_we(vec_we),
    .vec_addr(vec_addr),
    .motion_detected(motion_detected)
  );

  // Stimulus
  integer x, y;
  initial begin
    @(negedge rst);
    $display("=== Frame 1: Motion on right half ===");
    for (y = 0; y < V_ACTIVE; y = y + 1) begin
      for (x = 0; x < H_ACTIVE; x = x + 1) begin
        @(posedge pclk);
        s_pVDE  <= 1;
        // simulate a "moving block" only in right half of frame
        s_pData <= (x > H_ACTIVE/2) ? 24'hFFFFFF : 24'h000000;
      end
      @(posedge pclk);
      s_pVDE <= 0;
    end
    
    repeat (2000) @(posedge pclk);

    $display("=== Frame 2: Full black ===");
    for (y = 0; y < V_ACTIVE; y = y + 1) begin
      for (x = 0; x < H_ACTIVE; x = x + 1) begin
        @(posedge pclk);
        s_pVDE  <= 1;
        s_pData <= 24'h000000;
      end
      @(posedge pclk);
      s_pVDE <= 0;
    end

    #1000 $finish;
  end

  // Output monitor: show result every time a tile is processed
  always @(posedge pclk) begin
    if (vec_we) begin
      $display("[%0t] Tile %0d -> motion_detected = %b", $time, vec_addr, motion_detected);
    end
  end

endmodule

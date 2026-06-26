`timescale 1ns/1ps
module axi_top_ram_tb;

parameter DATA_WIDTH = 32;
parameter ADDR_WIDTH = 4;
parameter DEPTH      = 16;
parameter CLK_PERIOD = 10;

reg aclk;
reg areset_n;

// write address channel
reg  [ADDR_WIDTH-1:0] s_axi_awaddr;
reg                   s_axi_awvalid;
wire                  s_axi_awready;

// write data channel
reg  [DATA_WIDTH-1:0] s_axi_wdata;
reg                   s_axi_wvalid;
wire                  s_axi_wready;

// write response channel
wire [1:0]            s_axi_bresp;
wire                  s_axi_bvalid;
reg                   s_axi_bready;

// read channel
wire [DATA_WIDTH-1:0] s_axi_rdata;
wire [1:0]            rresp;
wire                  s_axi_rvalid;
reg                   s_axi_rready;
reg  [ADDR_WIDTH-1:0] s_axi_araddr;
reg                   s_axi_arvalid;
wire                  s_axi_arready;

integer error_count = 0;

// DUT
axi_top_ram #(
    .data_width(DATA_WIDTH),
    .addr_width(ADDR_WIDTH),
    .depth(DEPTH)
) dut (
    .aclk          (aclk),
    .areset_n      (areset_n),
    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),
    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),
    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),
    .s_axi_rdata   (s_axi_rdata),
    .rresp         (rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready),
    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready)
);

// clock
initial aclk = 0;
always #(CLK_PERIOD/2) aclk = ~aclk;

task axi_write;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] data;
    begin
        @(negedge aclk);
        s_axi_awaddr  = addr;
        s_axi_awvalid = 1;

        @(posedge aclk);
        while (!s_axi_awready) @(posedge aclk);
        @(negedge aclk);
        s_axi_awvalid = 0;

        s_axi_wdata  = data;
        s_axi_wvalid = 1;

        @(posedge aclk);
        while (!s_axi_wready) @(posedge aclk);
        @(negedge aclk);
        s_axi_wvalid = 0;

        s_axi_bready = 1;
        @(posedge aclk);
        while (!s_axi_bvalid) @(posedge aclk);
        @(negedge aclk);
        s_axi_bready = 0;

        if (s_axi_bresp !== 2'b00) begin
            $display("ERROR: write addr=%0h bresp=%b", addr, s_axi_bresp);
            error_count = error_count + 1;
        end else
            $display("OK   : wrote 0x%0h to addr=%0h | bresp=OKAY", data, addr);
    end
endtask

task axi_read;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] expected;
    reg   [DATA_WIDTH-1:0] rdata_capture;
    begin
        // -- address channel --
        @(negedge aclk);
        s_axi_araddr  = addr;
        s_axi_arvalid = 1;

        @(posedge aclk);
        while (!s_axi_arready) @(posedge aclk);
        @(negedge aclk);
        s_axi_arvalid = 0;

        // -- data channel --
        // keep rready LOW until rvalid appears
        s_axi_rready = 0;
        @(posedge aclk);
        while (!s_axi_rvalid) @(posedge aclk);

        // rvalid is high ? sample data at negedge (fully settled)
        @(negedge aclk);
        rdata_capture = s_axi_rdata;
        s_axi_rready  = 1;            // complete handshake

        @(posedge aclk);              // let FSM register the handshake
        @(negedge aclk);
        s_axi_rready = 0;

        if (rdata_capture !== expected) begin
            $display("FAIL : addr=%0h | expected=0x%0h | got=0x%0h",
                      addr, expected, rdata_capture);
            error_count = error_count + 1;
        end else
            $display("OK   : read  0x%0h from addr=%0h | rresp=OKAY",
                      rdata_capture, addr);
    end
endtask

initial begin
    areset_n      = 0;
    s_axi_awaddr  = 0;
    s_axi_awvalid = 0;
    s_axi_wdata   = 0;
    s_axi_wvalid  = 0;
    s_axi_bready  = 0;
    s_axi_araddr  = 0;
    s_axi_arvalid = 0;
    s_axi_rready  = 0;

    repeat(4) @(posedge aclk);
    @(negedge aclk);
    areset_n = 1;
    $display("--- reset released ---");

    axi_write(4'h0, 32'hDEAD_BEEF);
    axi_write(4'h1, 32'hCAFE_BABE);
    axi_write(4'h2, 32'h1234_5678);
    axi_write(4'h3, 32'hAAAA_5555);
    axi_write(4'hF, 32'hFFFF_FFFF);
    $display("--- all writes done ---");

    repeat(2) @(posedge aclk);

    $display("--- starting reads ---");
    axi_read(4'h0, 32'hDEAD_BEEF);
    axi_read(4'h1, 32'hCAFE_BABE);
    axi_read(4'h2, 32'h1234_5678);
    axi_read(4'h3, 32'hAAAA_5555);
    axi_read(4'hF, 32'hFFFF_FFFF);
    $display("--- all reads done ---");

    repeat(4) @(posedge aclk);

    if (error_count == 0)
        $display("=== TEST PASSED: all writes and reads matched ===");
    else
        $display("=== TEST FAILED: %0d mismatch(es) ===", error_count);

    $finish;
end

// waveform dump
initial begin
    $dumpfile("axi_ram.vcd");
    $dumpvars(0, axi_top_ram_tb);
end

// timeout watchdog
initial begin
    #10000;
    $display("TIMEOUT");
    $finish;
end

endmodule
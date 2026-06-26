module axi_top_ram #(parameter data_width = 32, addr_width = 4, depth = 16)(
input aclk, areset_n,

//write address channel
input [addr_width-1:0] s_axi_awaddr,
input s_axi_awvalid,
output s_axi_awready,

//write data channel
input [data_width-1:0] s_axi_wdata,
input s_axi_wvalid,
output reg s_axi_wready,

//write response channel
output reg [1:0] s_axi_bresp,
output reg s_axi_bvalid,
input s_axi_bready,

//read data channel
output reg [data_width-1:0] s_axi_rdata,
output reg [1:0] rresp,
output reg s_axi_rvalid,
input s_axi_rready,

//read address channel
input [addr_width-1:0] s_axi_araddr,
input s_axi_arvalid,
output s_axi_arready
);

//local parameters
localparam resp_okay    = 2'b00;
localparam resp_slv_err = 2'b10;

//write state machine parameters
localparam idle  = 2'b00;
localparam write = 2'b01;
localparam resp  = 2'b11;

//read state machine parameters  (FIX: split into addr-settle + data states)
localparam r_idle = 2'b00;
localparam r_addr = 2'b01;   // one cycle for read_addr_reg to settle
localparam r_data = 2'b10;   // ram_rdata is now valid for the new address

//internal signals
reg [1:0]            write_state, read_state;
reg [addr_width-1:0] write_addr_reg, read_addr_reg;

//ram interface signals
reg                   ram_write_enable;
wire [addr_width-1:0] ram_addr;
reg  [addr_width-1:0] ram_write_addr;   // FIX: registered alongside ram_write_data
reg  [data_width-1:0] ram_write_data;
wire [data_width-1:0] ram_rdata;

//instantiate the ram
ram_design #(.addr_width(addr_width), .data_width(data_width), .depth(depth))
    dut (aclk, areset_n, ram_write_enable, ram_addr, ram_write_data, ram_rdata);

// ram address mux ? write takes priority over read.
// FIX: gate on the registered ram_write_enable pulse itself (which is
// synchronous with ram_write_addr/ram_write_data) instead of the
// combinational write_state, which has already advanced to 'resp' by
// the cycle the write actually fires. Using write_state here caused the
// write to land at read_addr_reg's address instead of write_addr_reg's.
assign ram_addr = ram_write_enable ? ram_write_addr : read_addr_reg;

// ?? WRITE ADDRESS CHANNEL ????????????????????????????????????????
assign s_axi_awready = (write_state == idle);

always @(posedge aclk) begin
    if (!areset_n) begin
        write_addr_reg <= {addr_width{1'b0}};
        write_state    <= idle;
    end else begin
        case (write_state)
            idle:  if (s_axi_awvalid && s_axi_awready) begin
                       write_addr_reg <= s_axi_awaddr;
                       write_state    <= write;
                   end
            write: if (s_axi_wvalid && s_axi_wready)
                       write_state <= resp;
            resp:  if (s_axi_bvalid && s_axi_bready)
                       write_state <= idle;
            default: write_state <= idle;
        endcase
    end
end

// ?? WRITE DATA CHANNEL ???????????????????????????????????????????
always @(posedge aclk) begin
    if (!areset_n) begin
        s_axi_wready     <= 1'b0;
        ram_write_enable <= 1'b0;
        ram_write_addr   <= {addr_width{1'b0}};
        ram_write_data   <= {data_width{1'b0}};
    end else begin
        ram_write_enable <= 1'b0;          // default: clear every cycle
        if (write_state == write) begin
            s_axi_wready <= 1'b1;
            if (s_axi_wvalid && s_axi_wready) begin
                ram_write_addr   <= write_addr_reg; // FIX: latch addr with data
                ram_write_data   <= s_axi_wdata;
                ram_write_enable <= 1'b1;  // one-cycle pulse on handshake
            end
        end else begin
            s_axi_wready <= 1'b0;
        end
    end
end

// ?? WRITE RESPONSE CHANNEL ???????????????????????????????????????
always @(posedge aclk) begin
    if (!areset_n) begin
        s_axi_bvalid <= 1'b0;
        s_axi_bresp  <= resp_okay;
    end else begin
        if (write_state == write && s_axi_wvalid && s_axi_wready) begin
            // FIX: assert bvalid the cycle write-data handshake completes
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= resp_okay;
        end else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end
end

// ?? READ ADDRESS CHANNEL ?????????????????????????????????????????
assign s_axi_arready = (read_state == r_idle);

always @(posedge aclk) begin
    if (!areset_n) begin
        read_addr_reg <= {addr_width{1'b0}};
        read_state    <= r_idle;
    end else begin
        case (read_state)
            r_idle: if (s_axi_arvalid && s_axi_arready) begin
                        read_addr_reg <= s_axi_araddr;
                        read_state    <= r_addr;   // FIX: wait a cycle for addr_reg to settle
                    end
            r_addr: read_state <= r_data;          // ram_addr/ram_rdata now reflect new addr
            r_data: if (s_axi_rvalid && s_axi_rready)
                        read_state <= r_idle;
            default: read_state <= r_idle;
        endcase
    end
end

// ?? READ DATA CHANNEL ????????????????????????????????????????????
always @(posedge aclk) begin
    if (!areset_n) begin
        s_axi_rvalid <= 1'b0;
        s_axi_rdata  <= {data_width{1'b0}};
        rresp        <= 2'b00;
    end else begin
        // FIX: only load rdata/assert rvalid ONCE per transaction
        if (read_state == r_data && !s_axi_rvalid) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rdata  <= ram_rdata;  // ram_addr settled one cycle ago
            rresp        <= resp_okay;
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

endmodule

module ram_design #(parameter addr_width = 4, parameter data_width = 32, parameter depth = 16)(
input clk, reset_n, write_en,
input  [addr_width-1:0] addr,
input  [data_width-1:0] wdata,
output reg [data_width-1:0] rdata
);
reg [data_width-1:0] mem [0:depth-1];
integer i;
// synchronous write
always @(posedge clk) begin
    if (!reset_n) begin
        for (i = 0; i < depth; i = i + 1)
            mem[i] <= {data_width{1'b0}};
    end else begin
        if (write_en)
            mem[addr] <= wdata;
    end
end
// asynchronous read ? data available immediately when addr changes
always @(*) begin
    rdata = mem[addr];
end
endmodule

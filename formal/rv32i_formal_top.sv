`default_nettype none

// Bounded safety harness. Instruction/data responses are symbolic, so the
// bounded search explores arbitrary instruction encodings and data values.
// Reset is held across the first two formal clock edges. No liveness claim is made.
module rv32i_formal_top;
    (* gclk *) reg clk = 1'b0;
    always @($global_clock) clk <= !clk;

    reg [1:0] reset_count = 2'd0;
    reg rst_n = 1'b0;
    always @(posedge clk) begin
        if (reset_count != 2'd3)
            reset_count <= reset_count + 2'd1;
        rst_n <= (reset_count != 2'd0);
    end

    (* anyseq *) reg [31:0] imem_rdata;
    (* anyseq *) reg [31:0] dmem_rdata;

    wire [31:0] imem_addr;
    wire [31:0] dmem_addr, dmem_wdata;
    wire dmem_read, dmem_write;
    wire [3:0] dmem_wstrb;
    wire retire_valid, retire_rd_we, retire_store_we, stop;
    wire [31:0] retire_pc, retire_insn, retire_rd_data;
    wire [4:0] retire_rd;
    wire [31:0] retire_store_addr, retire_store_wdata;
    wire [3:0] retire_store_wstrb;
    wire [1:0] stop_cause;
    wire [31:0] stop_pc;

    rv32i_core dut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_read(dmem_read),
        .dmem_write(dmem_write), .dmem_wstrb(dmem_wstrb),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .retire_valid(retire_valid), .retire_pc(retire_pc),
        .retire_insn(retire_insn), .retire_rd_we(retire_rd_we),
        .retire_rd(retire_rd), .retire_rd_data(retire_rd_data),
        .retire_store_we(retire_store_we),
        .retire_store_addr(retire_store_addr),
        .retire_store_wstrb(retire_store_wstrb),
        .retire_store_wdata(retire_store_wdata),
        .stop(stop), .stop_cause(stop_cause), .stop_pc(stop_pc)
    );
endmodule

`default_nettype wire

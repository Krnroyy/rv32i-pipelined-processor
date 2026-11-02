`default_nettype none

// Standalone processor demonstration with combinational instruction/data reads.
// The tiny data store is byte-addressed, little-endian, and 64 bytes deep.
module rv32i_demo_system (
    input  wire       clk,
    input  wire       rst_n,
    output wire [3:0] leds,
    output logic      done,
    output wire       core_stop
);
    localparam logic [31:0] NOP = 32'h0000_0013;

    logic [31:0] imem [0:31];
    logic [31:0] dmem [0:15];
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata;
    logic [31:0] dmem_rdata;
    wire dmem_read, dmem_write;
    wire [3:0] dmem_wstrb;
    wire [31:0] retire_pc, retire_insn, retire_rd_data;
    wire retire_valid, retire_rd_we, retire_store_we;
    wire [4:0] retire_rd;
    wire [31:0] retire_store_addr, retire_store_wdata;
    wire [3:0] retire_store_wstrb;
    wire [1:0] stop_cause;
    wire [31:0] stop_pc;
    integer imem_i;
    integer dmem_i;

    // Demo program: 5 + 7, store 12, load it, add 1, store 13, then loop.
    initial begin
        for (imem_i = 0; imem_i < 32; imem_i = imem_i + 1) imem[imem_i] = NOP;
        imem[0] = 32'h0050_0093; // addi x1,x0,5
        imem[1] = 32'h0070_0113; // addi x2,x0,7
        imem[2] = 32'h0020_81b3; // add  x3,x1,x2
        imem[3] = 32'h0030_2023; // sw   x3,0(x0)
        imem[4] = 32'h0000_2203; // lw   x4,0(x0)
        imem[5] = 32'h0012_0293; // addi x5,x4,1 (load-use stall)
        imem[6] = 32'h0050_2223; // sw   x5,4(x0)
        imem[7] = 32'h0000_006f; // jal  x0,0
    end

    initial begin
        for (dmem_i = 0; dmem_i < 16; dmem_i = dmem_i + 1) dmem[dmem_i] = 32'b0;
    end

    assign imem_rdata = (imem_addr[31:7] == 0 && imem_addr[1:0] == 0)
                      ? imem[imem_addr[6:2]] : NOP;

    always_comb begin
        if (rst_n && dmem_read && dmem_addr[31:6] == 0)
            dmem_rdata = dmem[dmem_addr[5:2]];
        else
            dmem_rdata = 32'b0;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            done <= 1'b0;
        end else if (dmem_write && dmem_addr[31:6] == 0) begin
            if (dmem_wstrb[0]) dmem[dmem_addr[5:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) dmem[dmem_addr[5:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) dmem[dmem_addr[5:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) dmem[dmem_addr[5:2]][31:24] <= dmem_wdata[31:24];
            if (dmem_addr == 32'd4 && dmem_wstrb == 4'hf) done <= 1'b1;
        end
    end

    assign leds = core_stop ? 4'hf : (done ? dmem[1][3:0] : 4'h0);

    rv32i_core core_i (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_read(dmem_read), .dmem_write(dmem_write),
        .dmem_wstrb(dmem_wstrb), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .retire_valid(retire_valid), .retire_pc(retire_pc), .retire_insn(retire_insn),
        .retire_rd_we(retire_rd_we), .retire_rd(retire_rd), .retire_rd_data(retire_rd_data),
        .retire_store_we(retire_store_we), .retire_store_addr(retire_store_addr),
        .retire_store_wstrb(retire_store_wstrb), .retire_store_wdata(retire_store_wdata),
        .stop(core_stop), .stop_cause(stop_cause), .stop_pc(stop_pc)
    );
endmodule

`default_nettype wire

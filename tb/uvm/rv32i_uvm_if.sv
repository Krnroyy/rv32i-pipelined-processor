`timescale 1ns/1ps
`default_nettype none

interface rv32i_uvm_if(input wire clk);
    logic rst_n = 1'b0;
    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic dmem_read, dmem_write;
    logic [3:0] dmem_wstrb;
    logic retire_valid, retire_rd_we, retire_store_we;
    logic [31:0] retire_pc, retire_insn, retire_rd_data;
    logic [4:0] retire_rd;
    logic [31:0] retire_store_addr, retire_store_wdata;
    logic [3:0] retire_store_wstrb;
    logic stop;
    logic [1:0] stop_cause;
    logic [31:0] stop_pc;
    logic [31:0] imem [0:255];
    logic [7:0] dmem [0:4095];
    integer byte_base;
    int unsigned observed_write_count;
    int unsigned observed_pipeline_cycles;
    int unsigned observed_stalls;
    int unsigned forward_exmem_a, forward_exmem_b;
    int unsigned forward_memwb_a, forward_memwb_b;
    int unsigned observed_redirects;
    int unsigned observed_midrun_resets;
    int unsigned class_forward_count [0:5];
    int unsigned class_stall_count [0:5];
    int unsigned branch_fwd_taken, branch_fwd_untaken;
    int unsigned branch_no_fwd_taken, branch_no_fwd_untaken;

    always_comb begin
        imem_rdata = imem[imem_addr[9:2]];
        byte_base = {dmem_addr[11:2], 2'b00};
        dmem_rdata = {dmem[byte_base+3], dmem[byte_base+2],
                      dmem[byte_base+1], dmem[byte_base]};
    end

    always @(posedge clk) begin
        if (rst_n && dmem_write)
            begin
            observed_write_count = observed_write_count + 1;
            for (int lane=0; lane<4; lane++)
                if (dmem_wstrb[lane])
                    dmem[byte_base+lane] <= dmem_wdata[8*lane +: 8];
            end
    end
endinterface

`default_nettype wire

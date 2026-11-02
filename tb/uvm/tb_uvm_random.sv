`timescale 1ns/1ps
`default_nettype none

module tb_uvm_random;
    import uvm_pkg::*;
    import rv32i_uvm_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    rv32i_uvm_if vif(clk);
    rv32i_core dut (
        .clk(clk), .rst_n(vif.rst_n),
        .imem_addr(vif.imem_addr), .imem_rdata(vif.imem_rdata),
        .dmem_addr(vif.dmem_addr), .dmem_read(vif.dmem_read), .dmem_write(vif.dmem_write),
        .dmem_wstrb(vif.dmem_wstrb), .dmem_wdata(vif.dmem_wdata), .dmem_rdata(vif.dmem_rdata),
        .retire_valid(vif.retire_valid), .retire_pc(vif.retire_pc), .retire_insn(vif.retire_insn),
        .retire_rd_we(vif.retire_rd_we), .retire_rd(vif.retire_rd), .retire_rd_data(vif.retire_rd_data),
        .retire_store_we(vif.retire_store_we), .retire_store_addr(vif.retire_store_addr),
        .retire_store_wstrb(vif.retire_store_wstrb), .retire_store_wdata(vif.retire_store_wdata),
        .stop(vif.stop), .stop_cause(vif.stop_cause), .stop_pc(vif.stop_pc)
    );

    bit stall_seen, redirect_seen;
    logic [31:0] saved_pc, saved_ifid_pc, saved_ifid_insn, saved_redirect_target;
    integer cover_class;
    bit cover_forward;

    function automatic integer instruction_class(input bit [6:0] opcode);
        case (opcode)
            7'b0110011: instruction_class=0; // R
            7'b0010011: instruction_class=1; // I
            7'b0000011: instruction_class=2; // load
            7'b0100011: instruction_class=3; // store
            7'b1100011: instruction_class=4; // branch
            7'b1101111,7'b1100111: instruction_class=5; // jump
            default: instruction_class=-1;
        endcase
    endfunction

    property p_x0_stays_zero;
        @(posedge clk) disable iff (!vif.rst_n) dut.regs[0] == 32'b0;
    endproperty
    assert property (p_x0_stays_zero) else $fatal(1,"SVA: x0 changed from zero");

    property p_reset_gates_side_effects;
        @(posedge clk) !vif.rst_n |-> (!vif.retire_valid && !vif.dmem_read && !vif.dmem_write);
    endproperty
    assert property (p_reset_gates_side_effects) else $fatal(1,"SVA: reset did not gate architectural/memory outputs");

    property p_valid_store_request;
        @(posedge clk) disable iff (!vif.rst_n)
            vif.dmem_write |-> (dut.exmem_valid && dut.exmem_memwrite);
    endproperty
    assert property (p_valid_store_request) else $fatal(1,"SVA: store request from invalid/wrong slot");

    property p_valid_load_request;
        @(posedge clk) disable iff (!vif.rst_n)
            vif.dmem_read |-> (dut.exmem_valid && dut.exmem_memread);
    endproperty
    assert property (p_valid_load_request) else $fatal(1,"SVA: load request from invalid/wrong slot");

    property p_aligned_data_requests;
        @(posedge clk) disable iff (!vif.rst_n)
            (vif.dmem_read || vif.dmem_write) |->
                ((dut.exmem_insn[14:12] == 3'b000 || dut.exmem_insn[14:12] == 3'b100) ||
                 ((dut.exmem_insn[14:12] == 3'b001 || dut.exmem_insn[14:12] == 3'b101) && !vif.dmem_addr[0]) ||
                 (dut.exmem_insn[14:12] == 3'b010 && vif.dmem_addr[1:0] == 2'b00));
    endproperty
    assert property (p_aligned_data_requests) else $fatal(1,"SVA: misaligned data request escaped");

    property p_load_use_stall;
        @(posedge clk) disable iff (!vif.rst_n)
            dut.load_use_stall |=> ($stable(dut.pc_f) && $stable(dut.ifid_pc) &&
                                     $stable(dut.ifid_insn) && !dut.idex_valid);
    endproperty
    assert property (p_load_use_stall) else $fatal(1,"SVA: load-use stall failed to hold and bubble");

    property p_redirect_flush;
        @(posedge clk) disable iff (!vif.rst_n)
            (dut.ex_redirect && !dut.ex_fault) |=>
                (!dut.ifid_valid && !dut.idex_valid && dut.pc_f == $past(dut.ex_branch_target));
    endproperty
    assert property (p_redirect_flush) else $fatal(1,"SVA: redirect did not flush younger instructions");

    // Procedural cross-checks provide clear diagnostics alongside concurrent SVA.
    always @(posedge clk) begin
        stall_seen = 1'b0;
        redirect_seen = 1'b0;
        if (vif.rst_n) begin
            if (dut.ifid_valid || dut.idex_valid || dut.exmem_valid || dut.memwb_valid)
                vif.observed_pipeline_cycles++;
            if (dut.regs[0] !== 32'b0) $fatal(1,"ASSERT: x0 is not held at zero");
            if (vif.dmem_write && (!dut.exmem_valid || !dut.exmem_memwrite))
                $fatal(1,"ASSERT: data write without a valid store slot");
            if (vif.dmem_read && (!dut.exmem_valid || !dut.exmem_memread))
                $fatal(1,"ASSERT: data read without a valid load slot");
            if (dut.load_use_stall) begin
                stall_seen = 1'b1;
                vif.observed_stalls++;
                saved_pc = dut.pc_f;
                saved_ifid_pc = dut.ifid_pc;
                saved_ifid_insn = dut.ifid_insn;
                cover_class=instruction_class(dut.ifid_insn[6:0]);
                if (cover_class >= 0) vif.class_stall_count[cover_class]++;
            end
            if (dut.ex_redirect && !dut.ex_fault && !dut.stop) begin
                redirect_seen = 1'b1;
                vif.observed_redirects++;
                saved_redirect_target = dut.ex_branch_target;
            end
            if (dut.idex_valid && dut.idex_uses_rs1 && dut.idex_rs1!=0) begin
                if (dut.exmem_valid && dut.exmem_regwrite && !dut.exmem_memread && dut.exmem_rd==dut.idex_rs1)
                    vif.forward_exmem_a++;
                else if (dut.memwb_valid && dut.memwb_regwrite && dut.memwb_rd==dut.idex_rs1)
                    vif.forward_memwb_a++;
            end
            if (dut.idex_valid && dut.idex_uses_rs2 && dut.idex_rs2!=0) begin
                if (dut.exmem_valid && dut.exmem_regwrite && !dut.exmem_memread && dut.exmem_rd==dut.idex_rs2)
                    vif.forward_exmem_b++;
                else if (dut.memwb_valid && dut.memwb_regwrite && dut.memwb_rd==dut.idex_rs2)
                    vif.forward_memwb_b++;
            end
            if (dut.idex_valid) begin
                cover_class=instruction_class(dut.idex_insn[6:0]);
                cover_forward=1'b0;
                if (dut.idex_uses_rs1 && dut.idex_rs1!=0 &&
                    ((dut.exmem_valid && dut.exmem_regwrite && !dut.exmem_memread && dut.exmem_rd==dut.idex_rs1) ||
                     (dut.memwb_valid && dut.memwb_regwrite && dut.memwb_rd==dut.idex_rs1)))
                    cover_forward=1'b1;
                if (dut.idex_uses_rs2 && dut.idex_rs2!=0 &&
                    ((dut.exmem_valid && dut.exmem_regwrite && !dut.exmem_memread && dut.exmem_rd==dut.idex_rs2) ||
                     (dut.memwb_valid && dut.memwb_regwrite && dut.memwb_rd==dut.idex_rs2)))
                    cover_forward=1'b1;
                if (cover_class >= 0 && cover_forward)
                    vif.class_forward_count[cover_class]++;
                if (cover_class == 4) begin
                    if (cover_forward && dut.ex_branch_taken) vif.branch_fwd_taken++;
                    else if (cover_forward) vif.branch_fwd_untaken++;
                    else if (dut.ex_branch_taken) vif.branch_no_fwd_taken++;
                    else vif.branch_no_fwd_untaken++;
                end
            end
        end
    end

    always @(negedge clk) begin
        if (vif.rst_n && stall_seen) begin
            if (dut.pc_f !== saved_pc || dut.ifid_pc !== saved_ifid_pc ||
                dut.ifid_insn !== saved_ifid_insn || dut.idex_valid !== 1'b0)
                $fatal(1,"ASSERT: load-use stall did not hold IF/ID and insert ID/EX bubble");
        end
        if (vif.rst_n && redirect_seen) begin
            if (dut.pc_f !== saved_redirect_target || dut.ifid_valid !== 1'b0 || dut.idex_valid !== 1'b0)
                $fatal(1,"ASSERT: redirect did not set target and flush younger slots");
        end
    end

    initial begin
        for (int i=0;i<256;i++) vif.imem[i]=32'h0000_0013;
        for (int j=0;j<4096;j++) vif.dmem[j]=0;
        vif.observed_write_count=0;
        vif.observed_pipeline_cycles=0;
        vif.observed_midrun_resets=0;
        vif.observed_stalls=0;
        vif.forward_exmem_a=0; vif.forward_exmem_b=0;
        vif.forward_memwb_a=0; vif.forward_memwb_b=0;
        vif.observed_redirects=0;
        vif.branch_fwd_taken=0; vif.branch_fwd_untaken=0;
        vif.branch_no_fwd_taken=0; vif.branch_no_fwd_untaken=0;
        foreach (vif.class_forward_count[i]) vif.class_forward_count[i]=0;
        foreach (vif.class_stall_count[i]) vif.class_stall_count[i]=0;
        uvm_config_db#(virtual rv32i_uvm_if)::set(null,"*","vif",vif);
        run_test("rv32i_uvm_random_test");
    end

    // Assert a second reset after the first store/load have retired. Clear the
    // store instruction before replay so the next load proves reset preserved
    // data memory. The scoreboard
    // resets its architectural register/PC model but intentionally retains
    // byte memory, matching the core's documented reset behavior.
    initial begin : midrun_reset_stimulus
        int retired_before_reset;
        retired_before_reset=0;
        wait(vif.rst_n === 1'b1);
        while (retired_before_reset < 11) begin
            @(posedge clk);
            if (vif.retire_valid) retired_before_reset++;
        end
        @(negedge clk);
        vif.rst_n=1'b0;
        vif.observed_midrun_resets++;
        vif.imem[8]=32'h0000_0013; // first-prefix SW becomes NOP on replay
        repeat (2) @(negedge clk);
        vif.rst_n=1'b1;
    end

    initial begin
        #100000;
        $fatal(1,"UVM watchdog timeout");
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_rv32i_demo_system;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    wire [3:0] leds;
    wire done, core_stop;
    integer cycles;

    always #5 clk = ~clk;

    rv32i_demo_system dut (
        .clk(clk), .rst_n(rst_n), .leds(leds), .done(done), .core_stop(core_stop)
    );

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        cycles = 0;
        while (!done && cycles < 80) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        if (!done) $fatal(1, "FAIL: demo did not reach completion within 80 cycles");
        if (core_stop) $fatal(1, "FAIL: core stopped unexpectedly");
        if (dut.dmem[0] !== 32'd12) $fatal(1, "FAIL: first result expected 12, got %0d", dut.dmem[0]);
        if (dut.dmem[1] !== 32'd13) $fatal(1, "FAIL: second result expected 13, got %0d", dut.dmem[1]);
        if (leds !== 4'hd) $fatal(1, "FAIL: LEDs expected D, got %h", leds);

        $display("PASS: demo system; x3/store=12, load/add/store=13, LEDs=%h, cycles=%0d", leds, cycles);
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL: demo test watchdog expired");
    end
endmodule

`default_nettype wire

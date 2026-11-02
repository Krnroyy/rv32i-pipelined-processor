`default_nettype none

// ZCU104 board top. The board CPU_RESET pushbutton is active-high; reset
// assertion is asynchronous and deassertion is synchronized to the PL clock.
module rv32i_zcu104_top (
    input  wire       clk_125_p,
    input  wire       clk_125_n,
    input  wire       cpu_reset,
    output wire [3:0] leds
);
    wire clk_ibuf, core_clk;
    logic [1:0] reset_sync;
    wire rst_n = reset_sync[1];

    // Zynq UltraScale+ configuration initializes this synchronizer to reset.
    initial reset_sync = 2'b00;

`ifdef SYNTHESIS
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE")) clk_input_i (
        .I(clk_125_p), .IB(clk_125_n), .O(clk_ibuf)
    );
    BUFG clk_global_i (.I(clk_ibuf), .O(core_clk));
`else
    // Portable RTL simulation models the differential board clock by its P pin.
    assign clk_ibuf = clk_125_p;
    assign core_clk = clk_ibuf;
`endif

    always_ff @(posedge core_clk or posedge cpu_reset) begin
        if (cpu_reset) reset_sync <= 2'b00;
        else           reset_sync <= {reset_sync[0], 1'b1};
    end

    wire done, core_stop;
    rv32i_demo_system system_i (
        .clk(core_clk), .rst_n(rst_n), .leds(leds), .done(done), .core_stop(core_stop)
    );
endmodule

`default_nettype wire

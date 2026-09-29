//============================================================================
//
//  8255 PPI, mode 0 only (the Konami Galaxian-derived boards use nothing else)
//
//  Control word D7 = 1: mode set (D4 A in, D3 C upper in, D1 B in, D0 C lower
//  in; outputs cleared). D7 = 0: port C bit set/reset. Reading an output port
//  returns its latch.
//
//============================================================================

module galaxian_ppi
(
    input               clk,
    input               reset,

    input         [1:0] addr,
    input         [7:0] din,
    input               we,             // one clock per CPU write
    output reg    [7:0] dout,

    input         [7:0] pa_in,
    input         [7:0] pb_in,
    input         [7:0] pc_in,
    output reg    [7:0] pa_out = 8'd0,
    output reg    [7:0] pb_out = 8'd0,
    output reg    [7:0] pc_out = 8'd0,
    output              pc_we           // port C written (port write or bit set/reset)
);

reg [3:0] dir = 4'b1111;                // {A in, C upper in, B in, C lower in}: all inputs after reset

always @(posedge clk) begin
    if (reset) begin
        dir    <= 4'b1111;
        pa_out <= 8'd0;
        pb_out <= 8'd0;
        pc_out <= 8'd0;
    end
    else if (we) begin
        case (addr)
            2'd0: pa_out <= din;
            2'd1: pb_out <= din;
            2'd2: pc_out <= din;
            2'd3: if (din[7]) begin
                      dir    <= {din[4], din[3], din[1], din[0]};
                      pa_out <= 8'd0;
                      pb_out <= 8'd0;
                      pc_out <= 8'd0;
                  end
                  else pc_out[din[3:1]] <= din[0];
        endcase
    end
end

assign pc_we = we && (addr == 2'd2 || (addr == 2'd3 && !din[7]));

always @(*) begin
    case (addr)
        2'd0:    dout = dir[3] ? pa_in : pa_out;
        2'd1:    dout = dir[1] ? pb_in : pb_out;
        2'd2:    dout = {dir[2] ? pc_in[7:4] : pc_out[7:4], dir[0] ? pc_in[3:0] : pc_out[3:0]};
        default: dout = 8'hFF;
    endcase
end

endmodule

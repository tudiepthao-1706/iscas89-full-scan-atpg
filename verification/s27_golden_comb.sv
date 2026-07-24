module s27_golden_comb (
    input  logic g0,
    input  logic g1,
    input  logic g2,
    input  logic g3,

    // Current internal states in scan-chain order
    input  logic q_dff2,
    input  logic q_dff1,
    input  logic q_dff0,

    // Functional next states
    output logic d_dff2,
    output logic d_dff1,
    output logic d_dff0,

    // Functional primary output
    output logic g17
);

    logic g14;
    logic g8;
    logic g12;
    logic g15;
    logic g16;
    logic g9;

    always_comb begin
        // Original combinational logic from benchmarks/s27.v
        g14 = ~g0;
        g8  = g14 & q_dff1;

        g12 = ~(g1 | q_dff2);
        g15 = g12 | g8;
        g16 = g3 | g8;
        g9  = ~(g16 & g15);

        // Next states of DFF_1, DFF_0 and DFF_2
        d_dff1 = ~(q_dff0 | g9);
        d_dff0 = ~(g14 | d_dff1);
        d_dff2 = ~(g2 | g12);

        g17 = ~d_dff1;
    end

endmodule

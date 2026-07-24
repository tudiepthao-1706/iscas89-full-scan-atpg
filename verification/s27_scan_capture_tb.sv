`timescale 1ns/1ps

module tb_s27_scan_capture;

    localparam integer CHAIN_LEN = 8;

    logic CK;
    logic reset;

    logic GND;
    logic VDD;

    logic G0;
    logic G1;
    logic G2;
    logic G3;

    wire G17;

    logic sin;
    logic shift;
    wire  sout;
    logic tck;
    logic test;

    logic [CHAIN_LEN-1:0] input_stream;
    logic [CHAIN_LEN-1:0] observed_stream;
    logic [CHAIN_LEN-1:0] expected_stream;

    /*
     * Chain positions from sin toward sout:
     *
     *   loaded_chain[0] = G0 boundary input register
     *   loaded_chain[1] = G1 boundary input register
     *   loaded_chain[2] = G2 boundary input register
     *   loaded_chain[3] = G3 boundary input register
     *   loaded_chain[4] = DFF_2
     *   loaded_chain[5] = DFF_1
     *   loaded_chain[6] = DFF_0
     *   loaded_chain[7] = G17 boundary output register
     */
    logic [CHAIN_LEN-1:0] loaded_chain;
    logic [CHAIN_LEN-1:0] captured_chain;

    logic golden_dff2;
    logic golden_dff1;
    logic golden_dff0;
    logic golden_g17;

    integer i;
    integer k;

    s27 dut (
        .GND   (GND),
        .VDD   (VDD),
        .CK    (CK),
        .reset (reset),

        .G0    (G0),
        .G1    (G1),
        .G2    (G2),
        .G3    (G3),
        .G17   (G17),

        .sin   (sin),
        .shift (shift),
        .sout  (sout),
        .tck   (tck),
        .test  (test)
    );

    s27_golden_comb golden (
        .g0     (loaded_chain[0]),
        .g1     (loaded_chain[1]),
        .g2     (loaded_chain[2]),
        .g3     (loaded_chain[3]),

        .q_dff2 (loaded_chain[4]),
        .q_dff1 (loaded_chain[5]),
        .q_dff0 (loaded_chain[6]),

        .d_dff2 (golden_dff2),
        .d_dff1 (golden_dff1),
        .d_dff0 (golden_dff0),

        .g17    (golden_g17)
    );

    /*
     * input_stream is shifted LSB-first.
     *
     * After eight TCK pulses:
     *   chain position 0 contains input_stream[7]
     *   chain position 7 contains input_stream[0]
     */
    always_comb begin
        for (k = 0; k < CHAIN_LEN; k = k + 1)
            loaded_chain[k] = input_stream[CHAIN_LEN - 1 - k];

        // Input boundary registers hold during capture.
        captured_chain[0] = loaded_chain[0];
        captured_chain[1] = loaded_chain[1];
        captured_chain[2] = loaded_chain[2];
        captured_chain[3] = loaded_chain[3];

        // Internal scan FFs capture the functional next state.
        captured_chain[4] = golden_dff2;
        captured_chain[5] = golden_dff1;
        captured_chain[6] = golden_dff0;

        // Output boundary register captures G17.
        captured_chain[7] = golden_g17;

        /*
         * During unload, sout presents chain position 7 first,
         * followed by positions 6, 5, ..., 0.
         */
        for (k = 0; k < CHAIN_LEN; k = k + 1)
            expected_stream[k] =
                captured_chain[CHAIN_LEN - 1 - k];
    end

    task automatic pulse_tck;
        begin
            #2;
            tck = 1'b1;
            #2;
            tck = 1'b0;
            #2;
        end
    endtask

    initial begin
        $dumpfile("results/s27/s27_scan_capture.vcd");
        $dumpvars(0, tb_s27_scan_capture);

        GND = 1'b0;
        VDD = 1'b1;

        CK    = 1'b0;
        reset = 1'b1;

        G0 = 1'b0;
        G1 = 1'b0;
        G2 = 1'b0;
        G3 = 1'b0;

        sin   = 1'b0;
        shift = 1'b0;
        tck   = 1'b0;
        test  = 1'b0;

        observed_stream = '0;

        /*
         * Non-trivial pattern.
         *
         * For this pattern:
         *   loaded chain    = 01100101
         *   captured chain  = 11000101
         *   serial response = 10100011
         */
        input_stream = 8'b1010_0110;

        // Apply asynchronous reset.
        #5;
        reset = 1'b0;
        #5;

        // =========================================================
        // PHASE 1: SHIFT-IN
        // =========================================================
        test  = 1'b1;
        shift = 1'b1;

        for (i = 0; i < CHAIN_LEN; i = i + 1) begin
            sin = input_stream[i];
            pulse_tck();
        end

        #2;

        $display("========================================");
        $display("PHASE 1: SHIFT-IN");
        $display("Input serial stream : %b", input_stream);
        $display("Loaded chain state  : %b", loaded_chain);

        // =========================================================
        // PHASE 2: FUNCTIONAL CAPTURE
        // =========================================================
        shift = 1'b0;
        sin   = 1'b0;

        #2;

        $display("========================================");
        $display("PHASE 2: CAPTURE");
        $display("Expected captured chain: %b",
                 captured_chain);

        // One functional capture cycle.
        pulse_tck();

        #2;

        // =========================================================
        // PHASE 3: SHIFT-OUT
        // =========================================================
        shift = 1'b1;

        for (i = 0; i < CHAIN_LEN; i = i + 1) begin
            // Sample current sout before shifting the next bit.
            observed_stream[i] = sout;
            pulse_tck();
        end

        $display("========================================");
        $display("PHASE 3: SHIFT-OUT");
        $display("Expected serial response: %b",
                 expected_stream);
        $display("Observed serial response: %b",
                 observed_stream);

        if (observed_stream !== expected_stream) begin
            $fatal(
                1,
                "SHIFT-CAPTURE-SHIFT FAIL: expected %b, got %b",
                expected_stream,
                observed_stream
            );
        end

        /*
         * If capture did not occur, the response would simply equal
         * the original shift-in stream for this selected pattern.
         */
        if (observed_stream === input_stream) begin
            $fatal(
                1,
                "CAPTURE FAIL: response equals original input stream"
            );
        end

        $display("========================================");
        $display("SHIFT-CAPTURE-SHIFT PASS");
        $display("========================================");

        $finish;
    end

endmodule

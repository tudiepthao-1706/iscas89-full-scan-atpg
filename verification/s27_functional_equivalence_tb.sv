`timescale 1ns/1ps

module tb_s27_functional_equivalence;

    localparam integer NUM_CYCLES = 1000;

    logic GND;
    logic VDD;
    logic CK;
    logic reset;

    logic G0;
    logic G1;
    logic G2;
    logic G3;

    wire prescan_G17;
    wire postscan_G17;

    // Scan ports of the post-scan design
    logic sin;
    logic shift;
    wire  sout;
    logic tck;
    logic test;

    integer cycle;
    integer seed;

    s27_prescan prescan_dut (
        .GND   (GND),
        .VDD   (VDD),
        .CK    (CK),
        .reset (reset),
        .G0    (G0),
        .G1    (G1),
        .G2    (G2),
        .G3    (G3),
        .G17   (prescan_G17)
    );

    s27 postscan_dut (
        .GND   (GND),
        .VDD   (VDD),
        .CK    (CK),
        .reset (reset),
        .G0    (G0),
        .G1    (G1),
        .G2    (G2),
        .G3    (G3),
        .G17   (postscan_G17),

        .sin   (sin),
        .shift (shift),
        .sout  (sout),
        .tck   (tck),
        .test  (test)
    );

    task automatic pulse_functional_clock;
        begin
            #2;
            CK = 1'b1;
            #2;
            CK = 1'b0;
            #2;
        end
    endtask

    task automatic compare_outputs(
        input string checkpoint
    );
        begin
            if (prescan_G17 !== postscan_G17) begin
                $fatal(
                    1,
                    "FUNCTIONAL MISMATCH at cycle %0d (%s): pre-scan=%b post-scan=%b inputs=%b%b%b%b",
                    cycle,
                    checkpoint,
                    prescan_G17,
                    postscan_G17,
                    G0,
                    G1,
                    G2,
                    G3
                );
            end
        end
    endtask

    initial begin
        $dumpfile(
            "results/s27/s27_functional_equivalence.vcd"
        );
        $dumpvars(
            0,
            tb_s27_functional_equivalence
        );

        GND = 1'b0;
        VDD = 1'b1;
        CK  = 1'b0;

        G0 = 1'b0;
        G1 = 1'b0;
        G2 = 1'b0;
        G3 = 1'b0;

        /*
         * Keep the post-scan design permanently in functional mode.
         */
        test  = 1'b0;
        shift = 1'b0;
        sin   = 1'b0;
        tck   = 1'b0;

        seed = 32'h27A7_2026;

        // Apply reset to both designs.
        reset = 1'b1;
        #5;
        reset = 1'b0;
        #5;

        cycle = 0;
        compare_outputs("after reset");

        for (
            cycle = 0;
            cycle < NUM_CYCLES;
            cycle = cycle + 1
        ) begin
            /*
             * Drive the same deterministic pseudo-random inputs
             * into the pre-scan and post-scan designs.
             */
            {G0, G1, G2, G3} = $random(seed);

            #2;
            compare_outputs("before clock");

            pulse_functional_clock();

            #2;
            compare_outputs("after clock");
        end

        $display("========================================");
        $display(
            "FUNCTIONAL REGRESSION PASS: %0d cycles",
            NUM_CYCLES
        );
        $display(
            "Pre-scan and post-scan outputs matched in functional mode."
        );
        $display("========================================");

        $finish;
    end

endmodule

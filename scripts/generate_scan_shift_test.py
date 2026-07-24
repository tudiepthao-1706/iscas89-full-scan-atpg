#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Patch Fault's missing reset port and generate "
            "a self-checking scan-chain integrity testbench."
        )
    )
    parser.add_argument("--circuit", required=True)
    parser.add_argument("--netlist", required=True, type=Path)
    parser.add_argument("--outdir", required=True, type=Path)
    return parser.parse_args()


def extract_metadata(text: str) -> dict:
    match = re.search(
        r"FAULT METADATA:\s*'(\{.*?\})'\s*END FAULT METADATA",
        text,
        flags=re.DOTALL,
    )

    if match is None:
        raise RuntimeError("FAULT METADATA was not found")

    return json.loads(match.group(1))


def patch_rst_port(text: str, circuit: str) -> str:
    """
    Fault declares `input rst;` inside the generated top module,
    but omits rst from the module port list for s298 and s344.

    This function patches only a copy under build/.
    """

    pattern = re.compile(
        rf"(module\s+{re.escape(circuit)}\s*\()(.*?)(\);)",
        flags=re.DOTALL,
    )

    match = pattern.search(text)

    if match is None:
        raise RuntimeError(
            f"Top-level module {circuit!r} was not found"
        )

    raw_ports = match.group(2)

    ports = [
        token.strip()
        for token in raw_ports.split(",")
        if token.strip()
    ]

    if "rst" not in ports:
        raw_ports = raw_ports.rstrip() + ",\n  rst\n"

        text = (
            text[:match.start()]
            + match.group(1)
            + raw_ports
            + match.group(3)
            + text[match.end():]
        )

    if re.search(r"\binput\s+rst\s*;", text) is None:
        raise RuntimeError(
            "Generated top module does not declare `input rst;`"
        )

    return text


def validate_identifier(name: str) -> None:
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", name) is None:
        raise RuntimeError(
            f"Unsupported top-level port name: {name!r}"
        )


def main() -> None:
    args = parse_args()

    if not args.netlist.exists():
        raise FileNotFoundError(args.netlist)

    original_text = args.netlist.read_text(
        encoding="utf-8"
    )

    metadata = extract_metadata(original_text)
    scan_order = metadata["order"]

    chain_len = len(scan_order)

    input_ports = [
        item["name"]
        for item in scan_order
        if item["kind"] == "input"
    ]

    output_ports = [
        item["name"]
        for item in scan_order
        if item["kind"] == "output"
    ]

    for name in input_ports + output_ports:
        validate_identifier(name)

    args.outdir.mkdir(
        parents=True,
        exist_ok=True,
    )

    patched_path = (
        args.outdir
        / f"{args.circuit}_postscan_patched.v"
    )

    testbench_path = (
        args.outdir
        / f"{args.circuit}_scan_shift_tb.sv"
    )

    patched_text = patch_rst_port(
        original_text,
        args.circuit,
    )

    patched_path.write_text(
        patched_text,
        encoding="utf-8",
    )

    input_declarations = "\n".join(
        f"    logic {name};"
        for name in input_ports
    )

    output_declarations = "\n".join(
        f"    wire  {name};"
        for name in output_ports
    )

    input_initialization = "\n".join(
        f"        {name} = 1'b0;"
        for name in input_ports
    )

    connections = [
        ".GND(GND)",
        ".VDD(VDD)",
        ".CK(CK)",
    ]

    connections.extend(
        f".{name}({name})"
        for name in input_ports
    )

    connections.extend(
        f".{name}({name})"
        for name in output_ports
    )

    connections.extend(
        [
            ".sin(sin)",
            ".shift(shift)",
            ".sout(sout)",
            ".tck(tck)",
            ".test(test)",
            ".rst(rst)",
        ]
    )

    formatted_connections = ",\n        ".join(
        connections
    )

    testbench_text = f"""\
`timescale 1ns/1ps

module tb_{args.circuit}_scan_shift;

    localparam integer CHAIN_LEN = {chain_len};

    logic GND;
    logic VDD;
    logic CK;
    logic rst;

    logic sin;
    logic shift;
    wire  sout;
    logic tck;
    logic test;

{input_declarations}
{output_declarations}

    logic [CHAIN_LEN-1:0] expected_pattern;
    logic [CHAIN_LEN-1:0] observed_pattern;

    integer i;

    {args.circuit} dut (
        {formatted_connections}
    );

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
        $dumpfile(
            "results/{args.circuit}/{args.circuit}_scan_shift.vcd"
        );

        $dumpvars(
            0,
            tb_{args.circuit}_scan_shift
        );

        GND = 1'b0;
        VDD = 1'b1;
        CK  = 1'b0;
        rst = 1'b1;

        sin   = 1'b0;
        shift = 1'b0;
        tck   = 1'b0;
        test  = 1'b0;

{input_initialization}

        expected_pattern = '0;
        observed_pattern = '0;

        /*
         * Deterministic non-trivial scan pattern.
         * This is not an ATPG pattern.
         */
        for (i = 0; i < CHAIN_LEN; i = i + 1)
            expected_pattern[i] =
                ((i % 3) == 0) ^ ((i % 5) == 0);

        // Reset all generated scan storage registers.
        #5;
        rst = 1'b0;
        #5;

        test  = 1'b1;
        shift = 1'b1;

        // PHASE 1: SHIFT-IN
        for (i = 0; i < CHAIN_LEN; i = i + 1) begin
            sin = expected_pattern[i];
            pulse_tck();
        end

        /*
         * No functional capture is performed here.
         * This test verifies serial scan-chain integrity only.
         */

        // PHASE 2: SHIFT-OUT
        sin = 1'b0;

        for (i = 0; i < CHAIN_LEN; i = i + 1) begin
            observed_pattern[i] = sout;
            pulse_tck();
        end

        $display("========================================");
        $display("Circuit        : {args.circuit}");
        $display("Scan length    : %0d", CHAIN_LEN);
        $display("Expected stream: %b", expected_pattern);
        $display("Observed stream: %b", observed_pattern);

        if (observed_pattern !== expected_pattern) begin
            $fatal(
                1,
                "SCAN SHIFT FAIL: expected %b, got %b",
                expected_pattern,
                observed_pattern
            );
        end

        $display("SCAN SHIFT PASS");
        $display("========================================");

        $finish;
    end

endmodule
"""

    testbench_path.write_text(
        testbench_text,
        encoding="utf-8",
    )

    print(f"Generated patched netlist: {patched_path}")
    print(f"Generated testbench     : {testbench_path}")
    print(f"Chain length            : {chain_len}")
    print(f"Boundary inputs         : {len(input_ports)}")
    print(
        "Internal scan FFs       : "
        f"{metadata.get('internalCount', 'unknown')}"
    )
    print(f"Boundary outputs        : {len(output_ports)}")


if __name__ == "__main__":
    main()

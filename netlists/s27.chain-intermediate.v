

module BoundaryScanRegister_input
(
  din,
  dout,
  sin,
  sout,
  clock,
  reset,
  testing,
  shift
);

  input din;
  output dout;
  input sin;
  output sout;
  input clock;input reset;input testing;input shift;
  reg store;

  always @(posedge clock or posedge reset) begin
    if(reset) begin
      store <= 1'b0;
    end else begin
      store <= (shift)? sin : dout;
    end
  end

  assign sout = store;
  assign dout = (testing)? store : din;

endmodule



module BoundaryScanRegister_output
(
  din,
  dout,
  sin,
  sout,
  clock,
  reset,
  testing,
  shift
);

  input din;
  output dout;
  input sin;
  output sout;
  input clock;input reset;input testing;input shift;
  reg store;

  always @(posedge clock or posedge reset) begin
    if(reset) begin
      store <= 1'b0;
    end else begin
      store <= (shift)? sin : dout;
    end
  end

  assign sout = store;
  assign dout = din;

endmodule



module \s27.original 
(
  GND,
  VDD,
  CK,
  reset,
  G0,
  G1,
  G17,
  G2,
  G3,
  sin,
  shift,
  sout,
  tck,
  test
);

  input sin;
  output sout;
  input shift;
  input tck;
  input test;
  wire __clk_source__;
  wire __chain_0__;
  assign __chain_0__ = sin;
  wire _00_;
  wire _01_;
  wire _02_;
  wire _03_;
  wire _04_;
  wire _05_;
  wire _06_;
  wire _07_;
  input CK;
  wire CK;
  wire \DFF_0.D ;
  wire \DFF_0.Q ;
  wire \DFF_1.D ;
  wire \DFF_1.Q ;
  wire \DFF_2.D ;
  wire \DFF_2.Q ;
  input G0;
  wire G0;
  input G1;
  wire G1;
  output G17;
  wire G17;
  input G2;
  wire G2;
  input G3;
  wire G3;
  input GND;
  wire GND;
  input VDD;
  wire VDD;
  input reset;
  wire reset;

  INVX1
  _08_
  (
    .A(reset),
    .Y(_00_)
  );


  INVX1
  _09_
  (
    .A(G0),
    .Y(_03_)
  );


  INVX1
  _10_
  (
    .A(\DFF_0.Q ),
    .Y(_04_)
  );


  NOR2X1
  _11_
  (
    .A(G1),
    .B(\DFF_2.Q ),
    .Y(_05_)
  );


  AND2X1
  _12_
  (
    .A(G3),
    .B(_05_),
    .Y(_06_)
  );


  AOI22X1
  _13_
  (
    .A(_03_),
    .B(\DFF_1.Q ),
    .C(G3),
    .D(_05_),
    .Y(_07_)
  );


  NOR2X1
  _14_
  (
    .A(\DFF_0.Q ),
    .B(_07_),
    .Y(\DFF_1.D )
  );


  OR2X1
  _15_
  (
    .A(\DFF_0.Q ),
    .B(_07_),
    .Y(G17)
  );


  AOI21X1
  _16_
  (
    .A(_04_),
    .B(_06_),
    .C(_03_),
    .Y(\DFF_0.D )
  );


  NOR2X1
  _17_
  (
    .A(G2),
    .B(_05_),
    .Y(\DFF_2.D )
  );


  INVX1
  _18_
  (
    .A(reset),
    .Y(_01_)
  );


  INVX1
  _19_
  (
    .A(reset),
    .Y(_02_)
  );


  DFFSR
  _20_
  (
    .CLK(__clk_source__),
    .D((shift)? __chain_0__ : \DFF_2.D ),
    .Q(\DFF_2.Q ),
    .R(_00_),
    .S(1'b1)
  );


  DFFSR
  _21_
  (
    .CLK(__clk_source__),
    .D((shift)? \DFF_2.Q  : \DFF_1.D ),
    .Q(\DFF_1.Q ),
    .R(_01_),
    .S(1'b1)
  );


  DFFSR
  _22_
  (
    .CLK(__clk_source__),
    .D((shift)? \DFF_1.Q  : \DFF_0.D ),
    .Q(\DFF_0.Q ),
    .R(_02_),
    .S(1'b1)
  );

  assign sout = \DFF_0.Q ;
  assign __clk_source__ = (test)? tck : CK;

endmodule



module s27
(
  GND,
  VDD,
  CK,
  reset,
  G0,
  G1,
  G17,
  G2,
  G3,
  sin,
  shift,
  sout,
  tck,
  test
);

  input sin;
  output sout;
  input reset;
  input shift;
  input tck;
  input test;
  input CK;
  wire __chain_0__;
  assign __chain_0__ = sin;
  input GND;
  input VDD;
  input G0;
  wire G0__dout;
  wire __chain_1__;

  BoundaryScanRegister_input
  __BoundaryScanRegister_input__0__
  (
    .din(G0),
    .dout(G0__dout),
    .sin(__chain_0__),
    .sout(__chain_1__),
    .clock(tck),
    .reset(reset),
    .testing(test),
    .shift(shift)
  );

  input G1;
  wire G1__dout;
  wire __chain_2__;

  BoundaryScanRegister_input
  __BoundaryScanRegister_input__1__
  (
    .din(G1),
    .dout(G1__dout),
    .sin(__chain_1__),
    .sout(__chain_2__),
    .clock(tck),
    .reset(reset),
    .testing(test),
    .shift(shift)
  );

  input G2;
  wire G2__dout;
  wire __chain_3__;

  BoundaryScanRegister_input
  __BoundaryScanRegister_input__2__
  (
    .din(G2),
    .dout(G2__dout),
    .sin(__chain_2__),
    .sout(__chain_3__),
    .clock(tck),
    .reset(reset),
    .testing(test),
    .shift(shift)
  );

  input G3;
  wire G3__dout;
  wire __chain_4__;

  BoundaryScanRegister_input
  __BoundaryScanRegister_input__3__
  (
    .din(G3),
    .dout(G3__dout),
    .sin(__chain_3__),
    .sout(__chain_4__),
    .clock(tck),
    .reset(reset),
    .testing(test),
    .shift(shift)
  );

  wire __chain_5__;
  output G17;
  wire G17_din;
  wire __chain_6__;

  BoundaryScanRegister_output
  __BoundaryScanRegister_output__4__
  (
    .din(G17_din),
    .dout(G17),
    .sin(__chain_5__),
    .sout(__chain_6__),
    .clock(tck),
    .reset(reset),
    .testing(test),
    .shift(shift)
  );


  \s27.original 
  __uuf__
  (
    .GND(GND),
    .VDD(VDD),
    .CK(CK),
    .reset(reset),
    .G0(G0__dout),
    .G1(G1__dout),
    .G2(G2__dout),
    .G3(G3__dout),
    .shift(shift),
    .tck(tck),
    .test(test),
    .sin(__chain_4__),
    .sout(__chain_5__),
    .G17(G17_din)
  );

  assign sout = __chain_6__;

endmodule



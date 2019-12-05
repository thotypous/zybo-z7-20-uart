import AXI4_IFC::*;

interface TopIfc;
    interface AXI4_IFC axi;
endinterface

(* synthesize *)
module mkTop(TopIfc);
    AXI4_Adapter adapter <- mkAXI4_Adapter;

    interface AXI4_IFC axi = adapter.axi;
endmodule

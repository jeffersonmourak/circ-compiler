fn buildCircuit(circuit: *engine.Circuit) !struct {
    input_a: *engine.Component,
    output_out: *engine.Component,
} {
    const comp_a_0 = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
    const comp_out_1 = try circuit.createComponent(.{ .output_pin = .{} }, 1);
    try circuit.connect(comp_a_0.port("out"), comp_out_1.port("in"));
    return .{
        .input_a = comp_a_0,
        .output_out = comp_out_1,
    };
}

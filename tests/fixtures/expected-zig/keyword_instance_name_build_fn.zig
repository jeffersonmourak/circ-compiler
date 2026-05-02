fn buildCircuit(circuit: *engine.Circuit) !struct {
    input_a: *engine.Component,
    output_out: *engine.Component,
} {
    const comp_a_0 = try circuit.createComponent(.{ .input_pin_gate = .{} });
    const comp_error__1 = try circuit.createComponent(.{ .not_gate = .{} });
    const comp_out_2 = try circuit.createComponent(.{ .output_pin = .{} });
    try circuit.connect(comp_a_0.port("out"), comp_error__1.port("in"));
    try circuit.connect(comp_error__1.port("out"), comp_out_2.port("in"));
    return .{
        .input_a = comp_a_0,
        .output_out = comp_out_2,
    };
}

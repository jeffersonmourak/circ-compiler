fn buildCircuit(circuit: *engine.Circuit) !struct {
    input_a: *engine.Component,
    input_b: *engine.Component,
    output_result: *engine.Component,
} {
    const comp_a_0 = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
    const comp_b_1 = try circuit.createComponent(.{ .input_pin_gate = .{} }, 1);
    const comp_gate1_2 = try circuit.createComponent(.{ .and_gate = .{} }, 1);
    const comp_result_3 = try circuit.createComponent(.{ .output_pin = .{} }, 1);
    try circuit.connect(comp_a_0.port("out"), comp_gate1_2.port("a"));
    try circuit.connect(comp_b_1.port("out"), comp_gate1_2.port("b"));
    try circuit.connect(comp_gate1_2.port("out"), comp_result_3.port("in"));
    return .{
        .input_a = comp_a_0,
        .input_b = comp_b_1,
        .output_result = comp_result_3,
    };
}

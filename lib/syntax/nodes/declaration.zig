const C_Parser = @import("../CParser.zig").C_Parser;

pub fn translateDeclaration(_: [*c]C_Parser.ll_tree, _: C_Parser.ll_node_id) !void {
    return error.UnsupportedLegacyDeclarationTranslator;
}

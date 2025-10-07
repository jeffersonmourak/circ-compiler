
class CircRenderer {
    constructor(wasmPath: string) {
        console.log("Hello, world!");
        this.initializeWasm(wasmPath);
    }

    private async initializeWasm(wasmPath: string) {
        try {
            const wasm = await fetch(wasmPath);

            if (!wasm.ok) {
                throw new Error("Failed to fetch WASM file");
            }

            const wasmBuffer = await wasm.arrayBuffer();

            // console.log(wasmBuffer);
            // initialize wasm

            const wasmModule = await WebAssembly.instantiate(wasmBuffer, {});

            console.log(wasmModule);

            return wasm;
        } catch (error) {
            console.error(error);
        }
    }
}

export default CircRenderer;
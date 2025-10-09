

export enum ComponentKind {
    InputPinGate = 0,
    NotGate = 1,
    Led = 2,
    AndGate = 3,
    Wire = 4,
}

export enum State {
    Low = 0,
    High = 1,
    Undefined = 2,
}

export type CircRenderWasmExports = {
    init: () => void;
    deinit: () => void;
    createComponent: (kind: ComponentKind) => number;
    connect: (component1: number, pin1: number, component2: number, pin2: number) => void;
    propagateEvent: (component: number, state: State) => void;
    getComponentState: (component: number) => State;
    memory: WebAssembly.Memory;
}

export type CircRenderWasm<Exports> = WebAssembly.Instance & {
    exports: Exports;
}

export async function initializeWasm(wasmPath: string): Promise<CircRenderer> {
    try {
        const wasm = await fetch(wasmPath);

        if (!wasm.ok) {
            throw new Error("Failed to fetch WASM file");
        }

        const wasmBuffer = await wasm.arrayBuffer();

        const { instance } = await WebAssembly.instantiate(wasmBuffer, {
            env: {
                onStateChange: (component: number, state: number) => {
                    circRenderer.refreshState();
                }
            }
        });

        const circRenderer = new CircRenderer(instance as CircRenderWasm<CircRenderWasmExports>);

        return circRenderer;

    } catch (error) {
        throw new Error("Failed to initialize WASM");
    }
}

export class CircRenderer {
    private wasmInstance: CircRenderWasm<CircRenderWasmExports>;

    private nodes: Map<number, ComponentKind> = new Map();

    private states: Map<number, State> = new Map();

    constructor(wasmInstance: CircRenderWasm<CircRenderWasmExports>) {
        this.wasmInstance = wasmInstance;

        this.bootstrap();
    }

    private bootstrap() {
        this.wasmInstance.exports.init();
    }

    public circuit = {
        createComponent: (kind: ComponentKind) => {

            const id = this.wasmInstance.exports.createComponent(kind);
            this.nodes.set(id, kind);

            return id;
        },
        connect: (component1: number, pin1: number, component2: number, pin2: number) => {
            this.wasmInstance.exports.connect(component1, pin1, component2, pin2);
        },
        propagateEvent: (component: number, state: State) => {
            this.wasmInstance.exports.propagateEvent(component, state);
        },
        getComponentState: (component: number) => {
            return this.wasmInstance.exports.getComponentState(component);
        }
    }

    public refreshState() {
        for (const [id] of this.nodes) {
            const state = this.wasmInstance.exports.getComponentState(id);
            this.states.set(id, state);
        }

        this.printState();
    }

    public printState() {
        const states: number[] = [];
        for (const [id, state] of this.states) {
            states.push(state);
        }
        console.log(states);
    }
}
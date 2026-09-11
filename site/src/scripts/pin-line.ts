export interface PinValue {
  value: bigint;
  defined: bigint;
  width: number;
}

export interface PinRecord {
  name: string;
  kind: 'in' | 'out';
  value: PinValue;
}

export interface PinLinePart {
  text: string;
  name?: true;
}

interface TopologyLike {
  components: readonly {
    id: number;
    kind: number;
    name: string;
    origin: readonly unknown[];
  }[];
}

interface PinKinds {
  input: number;
  output: number;
}

/** Root pins, with inputs before outputs and each group in declaration order. */
export function rootPins(
  topology: TopologyLike,
  read: (id: number) => PinValue,
  kinds: PinKinds,
): PinRecord[] {
  const inputs: PinRecord[] = [];
  const outputs: PinRecord[] = [];
  for (const component of topology.components) {
    if (component.origin.length !== 0) continue;
    if (component.kind === kinds.input) {
      inputs.push({ name: component.name, kind: 'in', value: read(component.id) });
    } else if (component.kind === kinds.output) {
      outputs.push({ name: component.name, kind: 'out', value: read(component.id) });
    }
  }
  return [...inputs, ...outputs];
}

function formatValue(value: PinValue, format: 'hex' | 'binary' | 'decimal'): string {
  const mask = (1n << BigInt(value.width)) - 1n;
  if ((value.defined & mask) !== mask) return '?';
  const known = value.value & mask;
  if (value.width === 1) return known.toString(10);
  if (format === 'binary') return `0b${known.toString(2).padStart(value.width, '0')}`;
  if (format === 'decimal') return known.toString(10);
  return `0x${known.toString(16).toUpperCase().padStart(Math.ceil(value.width / 4), '0')}`;
}

function sideParts(pins: readonly PinRecord[], format: 'hex' | 'binary' | 'decimal'): PinLinePart[] {
  const parts: PinLinePart[] = [];
  pins.forEach((pin, index) => {
    if (index > 0) parts.push({ text: ' · ' });
    parts.push({ text: pin.name, name: true });
    parts.push({ text: ` = ${formatValue(pin.value, format)}` });
  });
  return parts;
}

export function pinLineParts(
  pins: readonly PinRecord[],
  format: 'hex' | 'binary' | 'decimal' = 'hex',
): PinLinePart[] {
  const inputs = sideParts(pins.filter((pin) => pin.kind === 'in'), format);
  const outputs = sideParts(pins.filter((pin) => pin.kind === 'out'), format);
  return inputs.length > 0 && outputs.length > 0
    ? [...inputs, { text: ' → ' }, ...outputs]
    : [...inputs, ...outputs];
}

export function pinLine(
  pins: readonly PinRecord[],
  format: 'hex' | 'binary' | 'decimal' = 'hex',
): string {
  return pinLineParts(pins, format).map((part) => part.text).join('');
}

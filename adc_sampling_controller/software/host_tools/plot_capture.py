import argparse
import math
import sys


def _iter_lines(path: str | None):
    if path is None or path == "-":
        for line in sys.stdin:
            yield line
        return
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            yield line


def parse_csv(lines):
    in_block = False
    rows = []
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        if line == "CSV_BEGIN":
            in_block = True
            continue
        if line == "CSV_END":
            break
        if in_block:
            if line.startswith("idx,"):
                continue
            parts = line.split(",")
            if len(parts) < 5:
                continue
            try:
                idx = int(parts[0], 10)
                addr = int(parts[1], 10)
                chan = int(parts[2], 10)
                code = int(parts[3], 10)
                volts = float(parts[4])
            except ValueError:
                continue
            rows.append((idx, addr, chan, code, volts))
        else:
            if not (line[0].isdigit() or (line[0] == "-" and len(line) > 1 and line[1].isdigit())):
                continue
            parts = line.split(",")
            if len(parts) < 5:
                continue
            try:
                idx = int(parts[0], 10)
                addr = int(parts[1], 10)
                chan = int(parts[2], 10)
                code = int(parts[3], 10)
                volts = float(parts[4])
            except ValueError:
                continue
            rows.append((idx, addr, chan, code, volts))
    return rows


def mean(values):
    if not values:
        return float("nan")
    return sum(values) / float(len(values))


def rms(values):
    if not values:
        return float("nan")
    return math.sqrt(sum(v * v for v in values) / float(len(values)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-i", "--input", default="-")
    ap.add_argument("--fft", action="store_true")
    ap.add_argument("--fs", type=float, default=None)
    ap.add_argument("--per-channel", action="store_true")
    args = ap.parse_args()

    rows = parse_csv(_iter_lines(args.input))
    if not rows:
        print("No CSV samples found. Provide a log containing CSV_BEGIN..CSV_END.", file=sys.stderr)
        return 2

    by_chan = {}
    for idx, addr, chan, code, volts in rows:
        by_chan.setdefault(chan, []).append((idx, volts))

    for chan in sorted(by_chan.keys()):
        values = [v for _, v in by_chan[chan]]
        print(f"chan={chan} n={len(values)} mean={mean(values):.6f} rms={rms(values):.6f}")

    try:
        import matplotlib.pyplot as plt
    except Exception as e:
        print(f"matplotlib import failed: {e}", file=sys.stderr)
        return 2

    if args.per_channel:
        fig, axes = plt.subplots(len(by_chan), 1, sharex=True)
        if len(by_chan) == 1:
            axes = [axes]
        for ax, chan in zip(axes, sorted(by_chan.keys())):
            pts = by_chan[chan]
            x = [i for i, _ in pts]
            y = [v for _, v in pts]
            ax.plot(x, y, linewidth=1.0)
            ax.set_ylabel(f"ch{chan} (V)")
        axes[-1].set_xlabel("sample index")
        fig.suptitle("ADC capture")
    else:
        plt.figure()
        for chan in sorted(by_chan.keys()):
            pts = by_chan[chan]
            x = [i for i, _ in pts]
            y = [v for _, v in pts]
            plt.plot(x, y, linewidth=1.0, label=f"ch{chan}")
        plt.xlabel("sample index")
        plt.ylabel("volts")
        plt.title("ADC capture")
        plt.legend()

    if args.fft:
        try:
            import numpy as np
        except Exception as e:
            print(f"numpy import failed: {e}", file=sys.stderr)
            return 2

        plt.figure()
        for chan in sorted(by_chan.keys()):
            y = np.array([v for _, v in by_chan[chan]], dtype=float)
            y = y - np.mean(y)
            spec = np.fft.rfft(y)
            mag = np.abs(spec) / max(1, y.size)
            if args.fs is not None:
                f = np.fft.rfftfreq(y.size, d=1.0 / args.fs)
                plt.plot(f, mag, linewidth=1.0, label=f"ch{chan}")
            else:
                plt.plot(mag, linewidth=1.0, label=f"ch{chan}")
        plt.title("FFT magnitude")
        plt.ylabel("magnitude")
        plt.xlabel("Hz" if args.fs is not None else "bin")
        plt.legend()

    plt.show()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


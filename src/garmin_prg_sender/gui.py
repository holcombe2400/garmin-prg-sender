from __future__ import annotations

import queue
import re
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path

import tkinter as tk
from tkinter import filedialog, messagebox, ttk


DEFAULT_ADDRESS = "F0:99:19:75:41:3E"
DEFAULT_PRG = r"C:\Users\holco\OneDrive\Documents\Garmin PRG Bluetooth Sender\test-prgs\GarmonInstallTest_fenix6pro_43KB.prg"


@dataclass(frozen=True)
class GuiPaths:
    root: Path
    python: Path
    sender: Path
    logs: Path


def discover_paths() -> GuiPaths:
    root = Path(__file__).resolve().parents[2]
    runtime_python = root / ".runtime" / "Scripts" / "python.exe"
    python = runtime_python if runtime_python.exists() else root / ".venv" / "Scripts" / "python.exe"
    sender = root / "send_prg.py"
    logs = root / "logs"
    return GuiPaths(root=root, python=python, sender=sender, logs=logs)


def command_base(paths: GuiPaths) -> list[str]:
    return [str(paths.python), "-u", "-B", str(paths.sender)]


def latest_log_path(logs: Path) -> Path | None:
    if not logs.exists():
        return None
    files: list[Path] = []
    for pattern in ("upload-*.jsonl", "stage-for-phone-sync-*.jsonl", "stage-for-garmin-connect-*.jsonl"):
        files.extend(logs.glob(pattern))
    files = sorted(files, key=lambda path: path.stat().st_mtime, reverse=True)
    return files[0] if files else None


def progress_percent_from_output(text: str) -> int | None:
    match = re.search(r"Uploaded\s+\d+/\d+\s+bytes\s+\((\d+)%\)", text)
    if not match:
        return None
    return max(0, min(100, int(match.group(1))))


def verification_status_from_output(text: str) -> str | None:
    if "NO_SPACE_FOR_TYPE" in text:
        return "PRG too large or no PRG storage available"
    if "NO_SPACE" in text:
        return "Not enough watch storage for this PRG"
    if "NO_SLOTS" in text or "No slots" in text:
        return "No Connect IQ app slots available"
    if "GFDI registration succeeded" in text or "GFDI transport initialized" in text:
        return "Connected to watch. Ready to send."
    if "Pair result: already paired" in text:
        return "Watch is already paired with Windows."
    if "Pair result: status=paired" in text:
        return "Watch paired with Windows."
    if "Windows says this device cannot be paired right now" in text:
        return "Put the watch in Pair Phone mode, then try Pair Watch again."
    if "No visible BLE device matched" in text:
        return "No matching watch found for pairing."
    if "PRG staged for Garmin Connect phone sync" in text:
        return "Upload complete. Turn phone Bluetooth back on."

    statuses = (
        "Transfer succeeded and app is registered",
        "Transfer succeeded but app is not registered",
        "Unable to query installed apps",
        "Garmon is registered",
        "Garmon is not registered",
        "BLE verification result: target is registered",
        "BLE verification result: target was not confirmed registered",
        "Index ladder stopped",
        "Index ladder completed",
        "Copy appears in GARMIN\\Apps",
        "Garmin USB device disappeared",
        "MTP did not return",
    )
    for status in statuses:
        if status in text:
            return status
    stripped = text.strip()
    if stripped.endswith(" is registered") or stripped.endswith(" is not registered"):
        return stripped
    return None


class SenderGui:
    def __init__(self, root: tk.Tk, paths: GuiPaths | None = None) -> None:
        self.root = root
        self.paths = paths or discover_paths()
        self.process: subprocess.Popen[str] | None = None
        self.output_queue: queue.Queue[object] = queue.Queue()
        self.active_label: str | None = None
        self.command_status: str | None = None

        root.title("Garmin PRG Sender")
        root.geometry("760x560")
        root.minsize(680, 460)

        self.address_var = tk.StringVar(value=DEFAULT_ADDRESS)
        self.prg_var = tk.StringVar(value=DEFAULT_PRG)
        self.status_var = tk.StringVar(
            value="Turn phone Bluetooth off first, then connect to the watch."
        )
        self.progress_var = tk.DoubleVar(value=0)
        self.progress_text_var = tk.StringVar(value="0%")
        self.details_visible = tk.BooleanVar(value=False)

        self.run_buttons: list[ttk.Button] = []
        self._build()
        self._set_running(False)
        self.root.after(100, self._drain_output)

    def _build(self) -> None:
        outer = ttk.Frame(self.root, padding=14)
        outer.pack(fill=tk.BOTH, expand=True)
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(5, weight=1)

        intro = ttk.Label(
            outer,
            text=(
                "Simple cable-free flow: choose a PRG, turn phone Bluetooth off, "
                "connect to the watch, send it, then turn phone Bluetooth back on."
            ),
            wraplength=720,
        )
        intro.grid(row=0, column=0, sticky="ew")

        prg = ttk.LabelFrame(outer, text="PRG file")
        prg.grid(row=1, column=0, sticky="ew", pady=(12, 0))
        prg.columnconfigure(1, weight=1)
        ttk.Label(prg, text="File").grid(row=0, column=0, padx=8, pady=8, sticky="w")
        ttk.Entry(prg, textvariable=self.prg_var).grid(row=0, column=1, padx=8, pady=8, sticky="ew")
        browse_button = ttk.Button(prg, text="Browse", command=self.browse_prg)
        browse_button.grid(row=0, column=2, padx=8, pady=8)

        watch = ttk.LabelFrame(outer, text="Watch")
        watch.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        watch.columnconfigure(1, weight=1)
        ttk.Label(watch, text="Address").grid(row=0, column=0, padx=8, pady=8, sticky="w")
        ttk.Entry(watch, textvariable=self.address_var).grid(row=0, column=1, padx=8, pady=8, sticky="ew")
        pair_button = ttk.Button(watch, text="Pair Watch", command=self.pair_watch)
        pair_button.grid(row=0, column=2, padx=8, pady=8, sticky="ew")
        self.run_buttons.append(pair_button)
        connect_button = ttk.Button(watch, text="Connect / Check Watch", command=self.connect_watch)
        connect_button.grid(row=0, column=3, padx=8, pady=8, sticky="ew")
        self.run_buttons.append(connect_button)

        actions = ttk.Frame(outer)
        actions.grid(row=3, column=0, sticky="ew", pady=(12, 0))
        actions.columnconfigure(0, weight=1)
        send_button = ttk.Button(actions, text="Send PRG to Watch", command=self.send_prg)
        send_button.grid(row=0, column=0, sticky="ew")
        self.run_buttons.append(send_button)
        check_button = ttk.Button(actions, text="Check Install", command=self.check_install)
        check_button.grid(row=0, column=1, padx=(8, 0))
        self.run_buttons.append(check_button)
        self.details_button = ttk.Button(actions, text="Show Details", command=self.toggle_details)
        self.details_button.grid(row=0, column=2, padx=(8, 0))
        self.stop_button = ttk.Button(actions, text="Stop", command=self.stop)
        self.stop_button.grid(row=0, column=3, padx=(8, 0))

        progress = ttk.Frame(outer)
        progress.grid(row=4, column=0, sticky="ew", pady=(12, 0))
        progress.columnconfigure(0, weight=1)
        self.progress_bar = ttk.Progressbar(progress, variable=self.progress_var, maximum=100)
        self.progress_bar.grid(row=0, column=0, sticky="ew")
        ttk.Label(progress, textvariable=self.progress_text_var, width=5).grid(row=0, column=1, padx=(8, 0))
        ttk.Label(progress, textvariable=self.status_var, wraplength=720).grid(
            row=1, column=0, columnspan=2, sticky="w", pady=(8, 0)
        )

        self.details_frame = ttk.LabelFrame(outer, text="Details")
        self.details_frame.grid(row=5, column=0, sticky="nsew", pady=(12, 0))
        self.details_frame.columnconfigure(0, weight=1)
        self.details_frame.rowconfigure(0, weight=1)
        self.output = tk.Text(self.details_frame, wrap=tk.WORD, height=12, undo=False)
        self.output.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(self.details_frame, command=self.output.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.output.configure(yscrollcommand=scroll.set)
        footer = ttk.Frame(self.details_frame)
        footer.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(8, 0))
        footer.columnconfigure(0, weight=1)
        ttk.Button(footer, text="Summarize Latest Log", command=self.summarize_latest_log).grid(row=0, column=0, sticky="w")
        ttk.Button(footer, text="Clear Details", command=self.clear_output).grid(row=0, column=1, sticky="e")
        self.details_frame.grid_remove()

    def browse_prg(self) -> None:
        current = self.prg_var.get()
        initialdir = str(Path(current).parent) if current else str(self.paths.root)
        path = filedialog.askopenfilename(
            title="Choose Garmin PRG",
            filetypes=[("Garmin PRG", "*.prg"), ("All files", "*.*")],
            initialdir=initialdir,
        )
        if path:
            self.prg_var.set(path)
            self._set_progress(0)
            self.status_var.set("PRG selected. Turn phone Bluetooth off, then connect to the watch.")

    def connect_watch(self) -> None:
        address = self._clean_address()
        if not address:
            messagebox.showerror("Missing watch address", "Enter the watch Bluetooth address first.")
            return
        self._set_progress(0)
        self._run(
            [
                "--probe-gfdi",
                "--address",
                address,
                "--winrt-services",
                "uncached",
                "--connect-timeout",
                "75",
                "--debug",
            ],
            "Connect to Watch",
        )

    def pair_watch(self) -> None:
        address = self._clean_address()
        if not address:
            messagebox.showerror("Missing watch address", "Enter the watch Bluetooth address first.")
            return
        self._set_progress(0)
        self._run(
            [
                "--pair-windows-ble",
                "--address",
                address,
                "--connect-timeout",
                "75",
                "--debug",
            ],
            "Pair Watch",
        )

    def send_prg(self) -> None:
        prg = self._selected_prg()
        if prg is None:
            return
        address = self._clean_address()
        if not address:
            messagebox.showerror("Missing watch address", "Enter the watch Bluetooth address first.")
            return

        self.paths.logs.mkdir(parents=True, exist_ok=True)
        log_path = self.paths.logs / "stage-for-phone-sync-latest.jsonl"
        self._set_progress(0)
        self._run(
            [
                "--stage-for-garmin-connect",
                "--file",
                str(prg),
                "--address",
                address,
                "--winrt-services",
                "uncached",
                "--connect-timeout",
                "75",
                "--timeout",
                "30",
                "--sync-timeout",
                "20",
                "--post-upload-trigger",
                "none",
                "--progress-step",
                "1",
                "--upload-retries",
                "5",
                "--packet-log",
                str(log_path),
                "--debug",
            ],
            "Send PRG to Watch",
        )

    def check_install(self) -> None:
        address = self._clean_address()
        if not address:
            messagebox.showerror("Missing watch address", "Enter the watch Bluetooth address first.")
            return
        self._run(
            [
                "--query-installed-apps",
                "--address",
                address,
                "--winrt-services",
                "uncached",
                "--connect-timeout",
                "75",
                "--timeout",
                "30",
                "--show-installed-apps",
                "--debug",
            ],
            "Check Install",
        )

    def summarize_latest_log(self) -> None:
        log_path = latest_log_path(self.paths.logs)
        if log_path is None:
            messagebox.showinfo("No logs", "No upload or stage logs were found yet.")
            return
        self._run(["--summarize-log", str(log_path)], "Summarize Latest Log")

    def toggle_details(self) -> None:
        visible = not self.details_visible.get()
        self.details_visible.set(visible)
        if visible:
            self.details_frame.grid()
            self.details_button.configure(text="Hide Details")
        else:
            self.details_frame.grid_remove()
            self.details_button.configure(text="Show Details")

    def clear_output(self) -> None:
        self.output.delete("1.0", tk.END)

    def stop(self) -> None:
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self._append("\nStopped current command.\n")
            self.status_var.set("Stopped")

    def _selected_prg(self) -> Path | None:
        raw = self.prg_var.get().strip().strip('"')
        if not raw:
            messagebox.showerror("Missing PRG", "Choose a PRG file first.")
            return None
        path = Path(raw)
        if not path.exists():
            messagebox.showerror("PRG not found", f"File not found:\n{path}")
            return None
        if path.suffix.lower() != ".prg":
            ok = messagebox.askyesno("Use this file?", "The selected file does not end in .prg. Try sending it anyway?")
            if not ok:
                return None
        return path

    def _clean_address(self) -> str:
        return self.address_var.get().strip().strip('"')

    def _run(self, args: list[str], label: str) -> None:
        if not self.paths.python.exists():
            messagebox.showerror("Missing Python", f"Python environment not found:\n{self.paths.python}")
            return
        if not self.paths.sender.exists():
            messagebox.showerror("Missing sender", f"Sender entry point not found:\n{self.paths.sender}")
            return
        self._run_command(command_base(self.paths) + args, label)

    def _run_command(self, command: list[str], label: str) -> None:
        if self.process and self.process.poll() is None:
            messagebox.showinfo("Busy", "A command is already running.")
            return

        self.active_label = label
        self.command_status = None
        self._append(f"\n== {label} ==\n")
        self._append(" ".join(f'"{part}"' if " " in part else part for part in command) + "\n")
        if label == "Connect to Watch":
            self.status_var.set("Connecting to watch...")
        elif label == "Pair Watch":
            self.status_var.set("Pairing watch with Windows...")
        elif label == "Send PRG to Watch":
            self.status_var.set("Sending PRG to watch...")
        else:
            self.status_var.set(f"Running: {label}")
        self._set_running(True)

        def worker() -> None:
            try:
                self.process = subprocess.Popen(
                    command,
                    cwd=str(self.paths.root),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                )
                assert self.process.stdout is not None
                for line in self.process.stdout:
                    self.output_queue.put(line)
                code = self.process.wait()
                self.output_queue.put(f"\nExit code: {code}\n")
                self.output_queue.put(("__DONE__", code))
            except Exception as exc:
                self.output_queue.put(f"\nError: {type(exc).__name__}: {exc}\n")
                self.output_queue.put(("__DONE__", 1))

        threading.Thread(target=worker, daemon=True).start()

    def _drain_output(self) -> None:
        while True:
            try:
                item = self.output_queue.get_nowait()
            except queue.Empty:
                break

            if isinstance(item, tuple) and item[0] == "__DONE__":
                code = int(item[1])
                self.process = None
                self._set_running(False)
                self._finish_command(code)
                continue

            text = str(item)
            percent = progress_percent_from_output(text)
            if percent is not None:
                self._set_progress(percent)
            status = verification_status_from_output(text)
            if status is not None:
                self.command_status = status
                self.status_var.set(status)
                if status.startswith("Upload complete"):
                    self._set_progress(100)
            self._append(text)
        self.root.after(100, self._drain_output)

    def _finish_command(self, code: int) -> None:
        label = self.active_label
        self.active_label = None
        if code != 0:
            if self.command_status == "No Connect IQ app slots available":
                self.status_var.set("No app slots available. Remove unused CIQ apps, then try again.")
            else:
                self.status_var.set("That did not complete. Show Details for the log.")
            return
        if self.command_status is not None:
            self.status_var.set(self.command_status)
            return
        if label == "Connect to Watch":
            self.status_var.set("Connection check finished.")
        elif label == "Pair Watch":
            self.status_var.set("Pairing finished. Connect to check watch.")
        elif label == "Send PRG to Watch":
            self._set_progress(100)
            self.status_var.set("Upload complete. Turn phone Bluetooth back on.")
        else:
            self.status_var.set("Done.")

    def _append(self, text: str) -> None:
        self.output.insert(tk.END, text)
        self.output.see(tk.END)

    def _set_progress(self, percent: int | float) -> None:
        value = max(0, min(100, float(percent)))
        self.progress_var.set(value)
        self.progress_text_var.set(f"{int(round(value))}%")

    def _set_running(self, running: bool) -> None:
        state = tk.DISABLED if running else tk.NORMAL
        for button in self.run_buttons:
            button.configure(state=state)
        self.stop_button.configure(state=tk.NORMAL if running else tk.DISABLED)


def main() -> int:
    root = tk.Tk()
    SenderGui(root)
    root.mainloop()
    return 0

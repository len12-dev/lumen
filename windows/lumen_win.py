"""Lumen pour Windows : liste les jeux Steam installés, les jeux de la base et les .exe ajoutés à la main.

Version simple (tkinter), compilée en .exe par GitHub Actions (voir .github/workflows/windows.yml).
"""
import json
import os
import re
import subprocess
import tkinter as tk
import urllib.request
from tkinter import filedialog, messagebox

API = os.environ.get("LUMEN_API", "http://192.168.1.123:8787")
DATA = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "Lumen", "games.json")
STEAM_TOOLS = {"228980"}  # Steamworks Shared : pas un jeu


def key(text):
    """Clé de rapprochement entre noms (sans casse, accents ni ponctuation)."""
    return re.sub(r"[^a-z0-9]", "", text.lower())


def steam_games():
    roots = [os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), "Steam")]
    libraries = []
    for root in roots:
        steamapps = os.path.join(root, "steamapps")
        libraries.append(steamapps)
        vdf = os.path.join(steamapps, "libraryfolders.vdf")
        if os.path.exists(vdf):
            with open(vdf, encoding="utf-8", errors="ignore") as f:
                for path in re.findall(r'"path"\s+"([^"]+)"', f.read()):
                    libraries.append(os.path.join(path.replace("\\\\", "\\"), "steamapps"))

    games = {}
    for folder in libraries:
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            if not (name.startswith("appmanifest_") and name.endswith(".acf")):
                continue
            with open(os.path.join(folder, name), encoding="utf-8", errors="ignore") as f:
                text = f.read()
            appid = re.search(r'"appid"\s+"(\d+)"', text)
            title = re.search(r'"name"\s+"([^"]+)"', text)
            if appid and title and appid.group(1) not in STEAM_TOOLS:
                games.setdefault(appid.group(1), title.group(1))
    return [{"name": n, "steam": i} for i, n in games.items()]


def custom_games():
    try:
        with open(DATA, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def save_custom(items):
    os.makedirs(os.path.dirname(DATA), exist_ok=True)
    with open(DATA, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)


def api_game_names():
    with urllib.request.urlopen(API + "/api/games", timeout=4) as response:
        return [g["name"] for g in json.load(response)["games"]]


def build_entries():
    """Jeux installés d'abord ; les jeux de la base sans installation locale sont listés sans lancement."""
    entries = [{"name": g["name"], "launch": {"steam": g["steam"]}} for g in steam_games()]
    entries += [{"name": c["name"], "launch": {"exe": c["exe"]}} for c in custom_games()]
    seen = {key(e["name"]) for e in entries}
    status = "base connectée"
    try:
        for name in api_game_names():
            if key(name) not in seen:
                entries.append({"name": name, "launch": None})
                seen.add(key(name))
    except OSError as error:
        status = f"base injoignable ({error.__class__.__name__})"
    return sorted(entries, key=lambda e: e["name"].lower()), status


class LumenWindows(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Lumen")
        self.geometry("720x480")
        self.configure(bg="#0e0f13")
        self.entries = []

        self.listbox = tk.Listbox(self, font=("Segoe UI", 16), bg="#171922", fg="white",
                                  selectbackground="#6ea8ff", selectforeground="black",
                                  borderwidth=0, highlightthickness=0, activestyle="none")
        self.listbox.pack(fill="both", expand=True, padx=16, pady=(16, 8))

        bar = tk.Frame(self, bg="#0e0f13")
        bar.pack(fill="x", padx=16, pady=(0, 8))
        for text, command in [("Lancer", self.launch), ("Ajouter un .exe", self.add_exe), ("Actualiser", self.refresh)]:
            tk.Button(bar, text=text, command=command).pack(side="left", padx=4)

        self.status = tk.StringVar()
        tk.Label(self, textvariable=self.status, bg="#0e0f13", fg="#8a8fa3", anchor="w").pack(fill="x", padx=16, pady=(0, 12))

        self.listbox.bind("<Double-Button-1>", lambda event: self.launch())
        self.bind("<Return>", lambda event: self.launch())
        self.bind("<Escape>", lambda event: self.destroy())
        self.refresh()

    def refresh(self):
        self.entries, status = build_entries()
        self.listbox.delete(0, "end")
        for entry in self.entries:
            suffix = "" if entry["launch"] else "  (pas installé)"
            self.listbox.insert("end", entry["name"] + suffix)
        self.status.set(f"{len(self.entries)} jeu(x) · {status}")

    def launch(self):
        selection = self.listbox.curselection()
        if not selection:
            return
        entry = self.entries[selection[0]]
        if not entry["launch"]:
            messagebox.showinfo("Lumen", "Ce jeu n'est pas installé sur ce PC.")
        elif "steam" in entry["launch"]:
            os.startfile(f"steam://rungameid/{entry['launch']['steam']}")
        else:
            exe = entry["launch"]["exe"]
            subprocess.Popen([exe], cwd=os.path.dirname(exe))

    def add_exe(self):
        path = filedialog.askopenfilename(filetypes=[("Application", "*.exe")])
        if not path:
            return
        items = custom_games()
        items.append({"name": os.path.splitext(os.path.basename(path))[0], "exe": path})
        save_custom(items)
        self.refresh()


if __name__ == "__main__":
    LumenWindows().mainloop()

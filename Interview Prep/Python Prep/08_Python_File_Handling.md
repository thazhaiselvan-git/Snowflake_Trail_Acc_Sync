# Python File Handling: Read, Write, Append, Load (All Options)

---

## 1. The generator function explained

```python
def read_large(path):
    with open(path) as f:          # open the file; it is closed automatically when done
        for line in f:             # the file object hands out ONE line at a time
            yield line.rstrip("\n")  # return the line without its newline, then pause
```

| Part | What it does |
|---|---|
| `with open(path) as f` | Opens the file and **always closes it**, even if an error happens |
| `for line in f` | Reads line by line, so the whole file is never loaded into memory |
| `yield` | Makes this a **generator**: it returns one value, pauses, and continues from there on the next request |
| `line.rstrip("\n")` | Removes the trailing newline (`"abc\n"` becomes `"abc"`) |

```python
for line in read_large("big_log.txt"):   # works on a 50 GB file with very little memory
    if "ERROR" in line:
        print(line)

gen = read_large("big_log.txt")
print(next(gen))   # first line only
```

Compare this with `f.read()` or `f.readlines()`, which load **the whole file** into memory and can crash on large files.

**Interview point:** a generator is lazy. Nothing is read until you loop over it, and it can only be used once.

---

## 2. `open()` and file modes

```python
f = open(path, mode="r", encoding="utf-8")
```

| Mode | Meaning | If the file doesn't exist | If the file exists |
|---|---|---|---|
| `"r"` | Read (default) | `FileNotFoundError` | Reads from the start |
| `"w"` | Write | Creates it | **Erases its contents** |
| `"a"` | Append | Creates it | Adds to the end |
| `"x"` | Create only | Creates it | `FileExistsError` |
| `"r+"` | Read and write | Error | Starts at the beginning, no erasing |
| `"w+"` | Write and read | Creates it | Erases its contents |
| `"a+"` | Append and read | Creates it | Writes always go to the end |
| add `"b"` | Binary (`"rb"`, `"wb"`, `"ab"`) | - | Bytes instead of text (images, PDFs, parquet) |

Always pass `encoding="utf-8"` for text files, because the default depends on the operating system.

---

## 3. Always use `with`

```python
# Good: the file is closed automatically
with open("data.txt", "r", encoding="utf-8") as f:
    content = f.read()

# Manual version (avoid it): you must remember close()
f = open("data.txt")
try:
    content = f.read()
finally:
    f.close()

# Several files at once
with open("in.txt") as src, open("out.txt", "w") as dst:
    dst.write(src.read())
```

---

## 4. Reading options

```python
with open("data.txt", encoding="utf-8") as f:
    text = f.read()          # whole file as ONE string
with open("data.txt", encoding="utf-8") as f:
    first10 = f.read(10)     # the first 10 characters
with open("data.txt", encoding="utf-8") as f:
    line = f.readline()      # one line (includes "\n"); '' at end of file
with open("data.txt", encoding="utf-8") as f:
    lines = f.readlines()    # list of all lines, each with "\n"
with open("data.txt", encoding="utf-8") as f:
    lines = f.read().splitlines()   # list of lines WITHOUT "\n"
with open("data.txt", encoding="utf-8") as f:
    for line in f:           # best for large files: memory efficient
        print(line.strip())
```

| Method | Returns | Memory |
|---|---|---|
| `f.read()` | One string | Whole file |
| `f.read(n)` | n characters | Small |
| `f.readline()` | One line | Small |
| `f.readlines()` | List of lines | Whole file |
| `for line in f` | One line per loop | **Small (best)** |

### Reading in fixed-size chunks (binary or huge files)

```python
def read_chunks(path, size=1024 * 1024):     # 1 MB per chunk
    with open(path, "rb") as f:
        while chunk := f.read(size):         # walrus operator (Python 3.8+)
            yield chunk
```

---

## 5. Writing (`"w"` replaces the contents)

```python
with open("out.txt", "w", encoding="utf-8") as f:
    f.write("Hello\n")                  # write() does NOT add a newline
    f.write("World\n")
    f.writelines(["a\n", "b\n"])        # writelines() does NOT add newlines either
    print("via print", file=f)          # print adds "\n" for you

rows = ["x", "y", "z"]
with open("out.txt", "w", encoding="utf-8") as f:
    f.write("\n".join(rows) + "\n")
```

## 6. Appending (`"a"` adds to the end)

```python
with open("log.txt", "a", encoding="utf-8") as f:
    f.write("new entry\n")              # existing content is kept

# A typical log-style append
from datetime import datetime
def log(msg, path="app.log"):
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")
log("job started")
```

### Safe create (fails if the file exists)

```python
try:
    with open("report.txt", "x") as f:
        f.write("first version")
except FileExistsError:
    print("already exists, not overwritten")
```

---

## 7. Position: `seek()` and `tell()`

```python
with open("data.txt", "r+", encoding="utf-8") as f:
    print(f.tell())      # 0, the current position
    f.read(5)
    print(f.tell())      # 5
    f.seek(0)            # go back to the start
    f.seek(0, 2)         # go to the end (whence=2); this form is safe in text mode
```

`tell()` and `seek()` count **bytes**. In text mode, only use `seek(0)`, `seek(0, 2)`, or a value you got from `tell()`.

---

## 8. Binary files

```python
with open("photo.jpg", "rb") as src, open("copy.jpg", "wb") as dst:
    dst.write(src.read())

data = b"\x00\x01"              # a bytes literal
text = data.decode("utf-8")     # bytes to str
raw = "hi".encode("utf-8")      # str to bytes
```

---

## 9. CSV files

```python
import csv

# Read as lists
with open("emp.csv", newline="", encoding="utf-8") as f:
    reader = csv.reader(f)
    header = next(reader)           # the first row
    for row in reader:
        print(row)                  # ['1', 'Alice', '5000'] (all values are strings)

# Read as dicts (best option)
with open("emp.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        print(row["name"], int(row["salary"]))

# Write
rows = [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]
with open("out.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["id", "name"])
    w.writeheader()
    w.writerows(rows)

# Append a row
with open("out.csv", "a", newline="", encoding="utf-8") as f:
    csv.writer(f).writerow([3, "Carol"])

# Other delimiters
csv.reader(f, delimiter="|")        # pipe-separated
csv.reader(f, delimiter="\t")       # TSV
```

Use `newline=""` with the csv module. Without it, you get blank lines between rows on Windows.

---

## 10. JSON files

```python
import json

data = {"name": "Selvan", "skills": ["SQL", "Python"]}

# Save (dump) and load
with open("data.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
with open("data.json", encoding="utf-8") as f:
    loaded = json.load(f)           # file to dict

# Strings: dumps/loads (the "s" stands for string)
s = json.dumps(data)                # dict to str
d = json.loads(s)                   # str to dict

# JSON Lines (one JSON object per line, common in data engineering)
with open("events.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps({"event": "click"}) + "\n")
with open("events.jsonl", encoding="utf-8") as f:
    events = [json.loads(line) for line in f]
```

| Function | Works with |
|---|---|
| `json.dump(obj, f)` / `json.load(f)` | File objects |
| `json.dumps(obj)` / `json.loads(s)` | Strings |

---

## 11. Pickle (saving Python objects)

```python
import pickle
with open("model.pkl", "wb") as f:
    pickle.dump({"a": [1, 2]}, f)
with open("model.pkl", "rb") as f:
    obj = pickle.load(f)
```

**Security:** never unpickle a file from an untrusted source, because loading it can run arbitrary code.

---

## 12. pandas (loading data for analysis)

```python
import pandas as pd

df = pd.read_csv("emp.csv")                       # also: sep="|", usecols=[...], dtype={...}
df = pd.read_json("data.json")
df = pd.read_json("events.jsonl", lines=True)
df = pd.read_excel("file.xlsx", sheet_name="Sheet1")   # needs openpyxl
df = pd.read_parquet("file.parquet")              # needs pyarrow

# Large CSV: process it in chunks
for chunk in pd.read_csv("big.csv", chunksize=100_000):
    print(len(chunk))

df.to_csv("out.csv", index=False)                 # write
df.to_csv("out.csv", mode="a", header=False, index=False)   # append
df.to_parquet("out.parquet")
```

---

## 13. `pathlib`, the modern way to work with paths

```python
from pathlib import Path

p = Path("data") / "emp.csv"        # joins paths correctly on any OS
print(p.name, p.stem, p.suffix)     # emp.csv emp .csv
print(p.parent)                     # data
print(p.exists(), p.is_file(), p.is_dir())

p.parent.mkdir(parents=True, exist_ok=True)   # create folders
p.write_text("id,name\n1,Alice\n", encoding="utf-8")
print(p.read_text(encoding="utf-8"))
p.write_bytes(b"...")               # binary write; read_bytes() reads it back

for f in Path("data").glob("*.csv"):    # list matching files (rglob searches subfolders)
    print(f)

print(p.stat().st_size)             # file size in bytes
```

---

## 14. File and folder operations (`os` and `shutil`)

```python
import os, shutil

os.path.exists("a.txt")             # True or False
os.path.getsize("a.txt")            # bytes
os.listdir(".")                     # list folder contents
os.makedirs("out/logs", exist_ok=True)
os.rename("a.txt", "b.txt")         # rename or move
os.remove("b.txt")                  # delete a file
os.rmdir("empty_dir")               # delete an EMPTY folder

shutil.copy("src.txt", "dst.txt")   # copy a file
shutil.move("src.txt", "archive/")  # move a file
shutil.rmtree("out")                # delete a folder and its contents (careful!)

for root, dirs, files in os.walk("."):   # walk a folder tree
    print(root, files)
```

---

## 15. Error handling

```python
try:
    with open("missing.txt", encoding="utf-8") as f:
        data = f.read()
except FileNotFoundError:
    print("File not found")
except PermissionError:
    print("No permission")
except UnicodeDecodeError:
    print("Wrong encoding; try encoding='latin-1' or errors='replace'")
except OSError as e:
    print("Other I/O error:", e)

# Skip or replace characters that can't be decoded
open("data.txt", encoding="utf-8", errors="ignore")     # or errors="replace"
```

---

## 16. Common interview problems

```python
# 1. Count lines, words and characters (like wc)
def wc(path):
    lines = words = chars = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            lines += 1
            words += len(line.split())
            chars += len(line)
    return lines, words, chars

# 2. The 3 most common words
from collections import Counter
with open("data.txt", encoding="utf-8") as f:
    print(Counter(f.read().lower().split()).most_common(3))

# 3. Last N lines of a big file (like tail)
from collections import deque
with open("app.log", encoding="utf-8") as f:
    last5 = deque(f, maxlen=5)

# 4. Filter ERROR lines into a new file (streaming, low memory)
with open("app.log", encoding="utf-8") as src, open("errors.log", "w", encoding="utf-8") as dst:
    for line in src:
        if "ERROR" in line:
            dst.write(line)

# 5. Merge every CSV in a folder
from pathlib import Path
import pandas as pd
df = pd.concat((pd.read_csv(p) for p in Path("data").glob("*.csv")), ignore_index=True)

# 6. Remove duplicate lines but keep their order
with open("in.txt", encoding="utf-8") as f:
    uniq = list(dict.fromkeys(line.rstrip("\n") for line in f))
```

---

## Summary

1. Always use `with open(...)` so the file is closed automatically.
2. `"w"` **erases** the contents, `"a"` **appends**, and `"x"` creates the file only if it doesn't exist.
3. For large files, use `for line in f` or a generator with `yield`. Avoid `read()` and `readlines()`.
4. `write()` doesn't add newlines, so add `"\n"` yourself.
5. Pass `encoding="utf-8"` for text files and `newline=""` for CSV files.
6. `json.load` and `json.dump` work with files, and `loads` and `dumps` work with strings.
7. Prefer `pathlib.Path` for paths, and use `shutil` to copy, move or delete trees.

# Python Core – Interview Questions & Answers

Focus: the fundamentals that come up in nearly every Data Engineer / Snowflake Developer interview.

---

## Section 1: Basics & Data Types

### Q1. What are Python's built-in data types?
| Category | Types |
|---|---|
| Numeric | `int`, `float`, `complex` |
| Sequence | `str`, `list`, `tuple`, `range` |
| Mapping | `dict` |
| Set | `set`, `frozenset` |
| Boolean | `bool` |
| Binary | `bytes`, `bytearray`, `memoryview` |
| None | `NoneType` |

### Q2. Mutable vs immutable?
- **Mutable** (can change in place): `list`, `dict`, `set`, `bytearray`
- **Immutable**: `int`, `float`, `str`, `tuple`, `frozenset`, `bytes`

```python
s = "abc"
# s[0] = "z"   -> TypeError
l = [1, 2]
l[0] = 9       # OK
```
Why it matters: only immutable (hashable) objects can be dict keys / set members.

### Q3. List vs Tuple vs Set vs Dict
| | List | Tuple | Set | Dict |
|---|---|---|---|---|
| Ordered | Yes | Yes | No | Yes (3.7+) |
| Mutable | Yes | No | Yes | Yes |
| Duplicates | Yes | Yes | No | Keys unique |
| Syntax | `[1,2]` | `(1,2)` | `{1,2}` | `{"a":1}` |
| Lookup | O(n) | O(n) | O(1) | O(1) by key |

### Q4. `is` vs `==`?
`==` compares **values**; `is` compares **identity** (same object in memory).
```python
a = [1, 2]; b = [1, 2]
a == b   # True
a is b   # False
x = None
x is None  # correct way to check None
```

### Q5. What is the difference between shallow copy and deep copy?
```python
import copy
orig = [[1, 2], [3, 4]]
sh = copy.copy(orig)      # new outer list, same inner lists
dp = copy.deepcopy(orig)  # everything copied recursively
orig[0][0] = 99
sh[0][0]  # 99  (shared)
dp[0][0]  # 1
```

### Q6. How does Python manage memory?
- Private heap managed by the Python memory manager.
- **Reference counting**: object freed when refcount hits 0.
- **Garbage collector** (`gc` module) handles reference cycles.
- Small ints (-5..256) and some strings are interned/cached.

### Q7. What are `*args` and `**kwargs`?
```python
def f(a, *args, **kwargs):
    print(a, args, kwargs)
f(1, 2, 3, x=10)   # 1 (2, 3) {'x': 10}
```
`*args` → extra positional args as tuple; `**kwargs` → extra keyword args as dict.

### Q8. Mutable default argument trap
```python
def add(item, lst=[]):     # BAD - list created once
    lst.append(item); return lst
add(1); add(2)             # [1, 2]  surprise!

def add(item, lst=None):   # GOOD
    if lst is None: lst = []
    lst.append(item); return lst
```

### Q9. What is the difference between `append()` and `extend()`?
```python
a = [1]; a.append([2, 3])  # [1, [2, 3]]
b = [1]; b.extend([2, 3])  # [1, 2, 3]
```

### Q10. `range` vs `list(range)`?
`range` is lazy (constant memory); `list(range(n))` materializes all n items.

---

## Section 2: Strings

### Q11. Common string operations
```python
s = "  Snowflake Data Cloud  "
s.strip()            # trim
s.lower(), s.upper()
s.split()            # ['Snowflake', 'Data', 'Cloud']
"-".join(["a","b"])  # 'a-b'
s.replace("Data", "AI")
s.find("Data")       # index or -1
s.startswith("  Snow")
f"{3.14159:.2f}"     # '3.14'
s[::-1]              # reverse
```

### Q12. Why is `"".join(list)` preferred over `+=` in a loop?
Strings are immutable, so `+=` creates a new string each time (O(n²)). `join` builds once (O(n)).

---

## Section 3: Comprehensions, Iterators, Generators

### Q13. List / dict / set comprehensions
```python
squares = [x*x for x in range(10) if x % 2 == 0]
d = {k: v for k, v in zip("abc", [1, 2, 3])}
uniq = {w.lower() for w in ["A", "a", "B"]}
```

### Q14. Iterator vs Iterable?
- **Iterable**: has `__iter__()` (list, str, dict).
- **Iterator**: has `__iter__()` and `__next__()`; remembers state; exhausted after one pass.
```python
it = iter([1, 2]); next(it); next(it); next(it)  # StopIteration
```

### Q15. What is a generator? Why use it?
A function using `yield`; produces values lazily → low memory. Ideal for reading huge files / streaming rows.
```python
def read_large(path):
    with open(path) as f:
        for line in f:
            yield line.rstrip("\n")

gen = (x*x for x in range(10**9))  # generator expression, no memory blow-up
```

### Q16. `yield` vs `return`?
`return` ends the function and sends one value. `yield` pauses, keeps local state, and resumes on next `next()`.

---

## Section 4: Functions & Functional Tools

### Q17. What is a lambda?
Anonymous one-expression function.
```python
sorted(emps, key=lambda e: e["salary"], reverse=True)
```

### Q18. `map`, `filter`, `reduce`
```python
from functools import reduce
list(map(str.upper, ["a", "b"]))           # ['A','B']
list(filter(lambda x: x > 2, [1, 2, 3, 4]))  # [3,4]
reduce(lambda a, b: a + b, [1, 2, 3])       # 6
```

### Q19. What is a closure?
An inner function that remembers variables from the enclosing scope.
```python
def multiplier(n):
    def inner(x): return x * n
    return inner
double = multiplier(2); double(5)  # 10
```

### Q20. What is a decorator? Write one.
A function that wraps another to add behaviour (logging, timing, retry, auth).
```python
import time, functools

def timer(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        print(f"{func.__name__} took {time.perf_counter()-start:.3f}s")
        return result
    return wrapper

@timer
def load_data(): time.sleep(1)
```

### Q21. Write a retry decorator (very common for DE roles)
```python
def retry(times=3, delay=2, exceptions=(Exception,)):
    def deco(func):
        @functools.wraps(func)
        def wrapper(*a, **kw):
            for attempt in range(1, times + 1):
                try:
                    return func(*a, **kw)
                except exceptions as e:
                    if attempt == times: raise
                    print(f"Attempt {attempt} failed: {e}; retrying")
                    time.sleep(delay * attempt)   # backoff
        return wrapper
    return deco
```

### Q22. LEGB scope rule
Name lookup order: **L**ocal → **E**nclosing → **G**lobal → **B**uilt-in. Use `global` / `nonlocal` to rebind outer names.

---

## Section 5: OOP

### Q23. Class basics, `__init__`, `self`
```python
class Warehouse:
    count = 0                       # class attribute
    def __init__(self, name, size):
        self.name = name            # instance attribute
        self.size = size
        Warehouse.count += 1
    def __repr__(self):
        return f"Warehouse({self.name!r}, {self.size!r})"
```

### Q24. Four pillars of OOP in Python
- **Encapsulation**: `_protected`, `__private` (name mangling).
- **Inheritance**: `class Child(Parent)`, `super().__init__()`.
- **Polymorphism**: same method name, different behaviour (duck typing).
- **Abstraction**: `abc.ABC` + `@abstractmethod`.

```python
from abc import ABC, abstractmethod
class Source(ABC):
    @abstractmethod
    def read(self): ...
class S3Source(Source):
    def read(self): return "reading S3"
```

### Q25. `@staticmethod` vs `@classmethod` vs instance method
```python
class Conn:
    def __init__(self, acct): self.acct = acct
    def info(self): return self.acct                 # needs instance
    @classmethod
    def from_env(cls): return cls(os.environ["ACCT"])  # alt constructor
    @staticmethod
    def validate(acct): return "." in acct            # utility, no self/cls
```

### Q26. What is MRO?
Method Resolution Order – order Python searches classes in multiple inheritance (C3 linearization). `ClassName.__mro__`.

### Q27. Magic / dunder methods
`__init__`, `__repr__`, `__str__`, `__len__`, `__eq__`, `__getitem__`, `__iter__`, `__enter__/__exit__` (context manager), `__call__`.

### Q28. What is `@property`?
```python
class Table:
    def __init__(self, rows): self._rows = rows
    @property
    def rows(self): return self._rows
    @rows.setter
    def rows(self, v):
        if v < 0: raise ValueError("negative")
        self._rows = v
```

### Q29. What are dataclasses?
```python
from dataclasses import dataclass, field
@dataclass
class Job:
    name: str
    retries: int = 3
    tags: list = field(default_factory=list)
```
Auto-generates `__init__`, `__repr__`, `__eq__`.

---

## Section 6: Exceptions & Context Managers

### Q30. try / except / else / finally
```python
try:
    cur.execute(sql)
except snowflake.connector.errors.ProgrammingError as e:
    log.error("SQL failed: %s", e)
    raise
else:
    log.info("success")          # runs only if no exception
finally:
    cur.close()                  # always runs
```

### Q31. Custom exception
```python
class DataQualityError(Exception):
    def __init__(self, table, failed):
        super().__init__(f"{table}: {failed} rows failed DQ")
```

### Q32. What is a context manager? Write one.
Guarantees setup/teardown via `with`.
```python
from contextlib import contextmanager
@contextmanager
def sf_cursor(conn):
    cur = conn.cursor()
    try:
        yield cur
    finally:
        cur.close()

with sf_cursor(conn) as cur:
    cur.execute("select current_version()")
```

---

## Section 7: Concurrency & Performance

### Q33. What is the GIL?
Global Interpreter Lock: only one thread executes Python bytecode at a time in CPython.
- **I/O-bound** (API calls, DB queries, S3 uploads) → `threading` / `ThreadPoolExecutor` / `asyncio` works well.
- **CPU-bound** → `multiprocessing` / `ProcessPoolExecutor`.

### Q34. Run multiple Snowflake queries in parallel
```python
from concurrent.futures import ThreadPoolExecutor, as_completed
def run(sql):
    with conn.cursor() as cur:
        return cur.execute(sql).fetchall()
with ThreadPoolExecutor(max_workers=4) as ex:
    futures = {ex.submit(run, q): q for q in queries}
    for f in as_completed(futures):
        print(futures[f], f.result())
```
(Snowflake also supports async queries: `cur.execute_async(sql)` + `conn.get_query_status(qid)`.)

### Q35. asyncio basics
```python
import asyncio
async def fetch(i):
    await asyncio.sleep(1); return i
async def main():
    return await asyncio.gather(*(fetch(i) for i in range(5)))
asyncio.run(main())   # ~1s total, not 5s
```

### Q36. How do you optimize slow Python code?
1. Profile first (`cProfile`, `time.perf_counter`).
2. Use right data structure (set/dict for lookups).
3. Vectorize with pandas/NumPy instead of loops.
4. Use generators for big data.
5. Push computation down to Snowflake (SQL / Snowpark) instead of pulling data to the client.
6. Cache: `functools.lru_cache`.

---

## Section 8: Modules, Packaging, Environment

### Q37. `if __name__ == "__main__":` – why?
Code under it runs only when the file is executed directly, not when imported.

### Q38. Virtual environments
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pip freeze > requirements.txt
```
Isolates dependencies per project. (Also: conda, poetry, uv.)

### Q39. How do you manage secrets / config in Python?
Never hardcode. Use env vars (`os.environ`), `.env` + `python-dotenv`, a secrets manager (AWS Secrets Manager / Azure Key Vault), or for Snowflake: key-pair auth + `connections.toml`, and Snowflake `SECRET` objects for UDFs/procs.

### Q40. Logging vs print
```python
import logging
logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger(__name__)
log.info("Loaded %d rows", n)
```
Levels, handlers, formatting, can route to files/CloudWatch – `print` can't.

---

## Section 9: Quick-fire

| Question | Answer |
|---|---|
| Python is compiled or interpreted? | Compiled to bytecode (`.pyc`), then interpreted by the PVM |
| `pass` vs `continue` vs `break` | no-op / skip to next iteration / exit loop |
| `del` vs `remove()` vs `pop()` | delete by index/name / by value / by index and return |
| What is `__init__.py`? | Marks a directory as a package (optional since 3.3) |
| Negative indexing | `l[-1]` last element |
| Slicing | `l[start:stop:step]` |
| `enumerate` | `for i, v in enumerate(l)` |
| `zip` | pair iterables: `dict(zip(keys, vals))` |
| `any` / `all` | any truthy / all truthy |
| Type hints | `def f(x: int) -> str:` – not enforced at runtime; checked with mypy |
| `sorted()` vs `.sort()` | returns new list / in place, returns None |
| PEP 8 | style guide (snake_case, 4 spaces, 79/99 chars) |
| `collections` | `Counter`, `defaultdict`, `deque`, `namedtuple`, `OrderedDict` |
| Walrus `:=` | assign in expression: `while (chunk := f.read(1024)):` |
| `match` (3.10) | structural pattern matching |

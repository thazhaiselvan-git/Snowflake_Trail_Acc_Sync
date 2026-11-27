# Python Comprehensions: List, Dict, Set and Generator

A comprehension is a short way to build a list, dict or set from a loop in one line.

General form: **`[expression for item in iterable if condition]`**. The bracket type decides what gets built.

---

## 1. List comprehension `[...]`

```python
squares = [x*x for x in range(10) if x % 2 == 0]
print(squares)   # [0, 4, 16, 36, 64]
```

Read it as "x*x, for each x in 0 to 9, but only if x is even." It does the same thing as this loop:

```python
squares = []
for x in range(10):
    if x % 2 == 0:
        squares.append(x*x)
```

More examples:

```python
names = [" alice ", "BOB", "Carol "]
print([n.strip().title() for n in names])     # ['Alice', 'Bob', 'Carol']

# if/else goes BEFORE the for (it transforms every item)
print(["even" if x % 2 == 0 else "odd" for x in range(4)])
# ['even', 'odd', 'even', 'odd']

# A plain if goes AFTER the for (it filters items out)
print([x for x in [5, -2, 8, -1] if x > 0])   # [5, 8]

# Nested loops: flatten a 2D list
matrix = [[1, 2], [3, 4], [5, 6]]
print([n for row in matrix for n in row])     # [1, 2, 3, 4, 5, 6]
```

## 2. Dict comprehension `{k: v ...}`

```python
d = {k: v for k, v in zip("abc", [1, 2, 3])}
print(d)   # {'a': 1, 'b': 2, 'c': 3}
```

`zip` pairs the two iterables as `('a',1), ('b',2), ('c',3)`. Each pair is unpacked into `k, v` and becomes `key: value`. In this case, `dict(zip("abc", [1, 2, 3]))` gives the same result.

More examples:

```python
words = ["snowflake", "data", "ai"]
print({w: len(w) for w in words})         # {'snowflake': 9, 'data': 4, 'ai': 2}

prices = {"pen": 10, "book": 250, "bag": 900}
print({k: v for k, v in prices.items() if v > 100})  # {'book': 250, 'bag': 900}

# Swap keys and values
print({v: k for k, v in prices.items()})  # {10: 'pen', 250: 'book', 900: 'bag'}

# Apply a 10% discount
print({k: v * 0.9 for k, v in prices.items()})  # {'pen': 9.0, 'book': 225.0, 'bag': 810.0}
```

If a key repeats, the last value wins: `{k: v for k, v in [("a", 1), ("a", 2)]}` gives `{'a': 2}`.

## 3. Set comprehension `{...}`

```python
uniq = {w.lower() for w in ["A", "a", "B"]}
print(uniq)   # {'a', 'b'} (the order may vary)
```

Each word is lowercased first (`'a', 'a', 'b'`), and then the set keeps only unique values.

More examples:

```python
emails = ["x@gmail.com", "y@yahoo.com", "z@gmail.com"]
print({e.split("@")[1] for e in emails})  # {'gmail.com', 'yahoo.com'}

print({x % 3 for x in range(10)})         # {0, 1, 2}
```

## 4. Generator expression `(...)`

```python
total = sum(x*x for x in range(1_000_000))  # no list is built
gen = (x*x for x in range(3))
print(next(gen), next(gen))                 # 0 1
```

A generator produces values lazily, one at a time, so it uses very little memory. That makes it the better choice for large data or values you only use once. There's **no tuple comprehension**: `(...)` gives you a generator, and `tuple(x for x in ...)` builds a tuple.

---

## Quick comparison

| Syntax | Builds | Example output |
|---|---|---|
| `[x for x in it]` | list (ordered, keeps duplicates) | `[0, 4, 16]` |
| `{k: v for ...}` | dict | `{'a': 1}` |
| `{x for x in it}` | set (unique, unordered) | `{'a', 'b'}` |
| `(x for x in it)` | generator (lazy) | `<generator object>` |

## Interview tips

1. `{}` on its own is an empty **dict**, not a set. Use `set()` for an empty set.
2. A comprehension is usually faster than the equivalent loop that calls `.append()`.
3. `if/else` before the `for` transforms values, and `if` after the `for` filters them.
4. If a comprehension gets hard to read, for example with more than two loops, use a normal loop.

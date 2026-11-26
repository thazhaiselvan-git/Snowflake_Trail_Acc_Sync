# Python Data Types – Beginner Guide (one line + small example each)

Tip: `type(x)` tells you the data type of any value. Lines starting with `#` are comments; `# ->` shows the output.

---

## 1. Numbers

**int** – a whole number, with no decimal point.
```python
age = 25
print(type(age))      # -> <class 'int'>
```

**float** – a number with a decimal point.
```python
price = 99.50
print(price * 2)      # -> 199.0
```

**complex** – a number with a real and an imaginary part (rarely used in data work).
```python
z = 3 + 4j
print(z.real)         # -> 3.0
```

---

## 2. Text

**str (string)** – text written inside single or double quotes.
```python
name = "Snowflake"
print(name.upper())   # -> SNOWFLAKE
print(name[0])        # -> S   (first character)
print(len(name))      # -> 9
```

---

## 3. True / False

**bool** – holds only `True` or `False`, and is used in conditions.
```python
is_active = True
print(10 > 5)         # -> True
```

---

## 4. Nothing

**NoneType (None)** – means "no value" (like NULL in SQL).
```python
result = None
print(result is None) # -> True
```

---

## 5. Collections (hold many values)

**list** – an ordered collection you can change; duplicates are allowed. Written with `[ ]`.
```python
fruits = ["apple", "banana", "apple"]
fruits.append("mango")
print(fruits)         # -> ['apple', 'banana', 'apple', 'mango']
print(fruits[1])      # -> banana
```

**tuple** – an ordered collection you **cannot** change after creating it. Written with `( )`.
```python
point = (10, 20)
print(point[0])       # -> 10
# point[0] = 5        # error: tuples can't be changed
```

**range** – a sequence of numbers, mostly used in loops.
```python
print(list(range(1, 5)))   # -> [1, 2, 3, 4]   (end number not included)
```

**set** – an unordered collection of **unique** values. Written with `{ }`.
```python
ids = {1, 2, 2, 3}
print(ids)            # -> {1, 2, 3}   (duplicate removed)
```

**frozenset** – a set that cannot be changed.
```python
fs = frozenset([1, 2, 3])
print(2 in fs)        # -> True
```

**dict (dictionary)** – stores **key: value** pairs, so you look up values by key (like a column name → value).
```python
emp = {"name": "Ravi", "salary": 50000}
print(emp["name"])    # -> Ravi
emp["city"] = "Chennai"
print(emp)            # -> {'name': 'Ravi', 'salary': 50000, 'city': 'Chennai'}
```

---

## 6. Binary (raw bytes – used for files/network)

**bytes** – raw data that cannot be changed.
```python
b = b"hi"
print(b[0])           # -> 104   (byte value of 'h')
```

**bytearray** – raw bytes that **can** be changed.
```python
ba = bytearray(b"hi")
ba[0] = 72
print(ba)             # -> bytearray(b'Hi')
```

**memoryview** – lets you look at bytes without copying them (advanced, used for performance).
```python
mv = memoryview(b"abc")
print(mv[0])          # -> 97
```

---

## 7. Converting between types (type casting)

```python
int("10")         # -> 10        str to int
float("3.5")      # -> 3.5       str to float
str(100)          # -> '100'     int to str
list("abc")       # -> ['a', 'b', 'c']
set([1, 1, 2])    # -> {1, 2}
tuple([1, 2])     # -> (1, 2)
bool(0)           # -> False     (0, "", [], None are False; most else True)
```

---

## 8. Cheat sheet

| Type | Example | Ordered? | Changeable? | Duplicates? |
|---|---|---|---|---|
| int | `5` | - | No | - |
| float | `5.5` | - | No | - |
| str | `"hi"` | Yes | No | Yes |
| bool | `True` | - | No | - |
| None | `None` | - | - | - |
| list | `[1, 2]` | Yes | **Yes** | Yes |
| tuple | `(1, 2)` | Yes | No | Yes |
| set | `{1, 2}` | No | **Yes** | **No** |
| dict | `{"a": 1}` | Yes | **Yes** | Keys: No |

"Changeable" = **mutable**. Interviewers ask this a lot: list, dict and set are mutable; int, float, str and tuple are immutable.

---

## 9. Practice (try these yourself)

1. Make a list of 3 cities, add one more, and print the second city.
2. Make a dict for a student (name, age, marks) and print only the marks.
3. Remove duplicates from `[1, 2, 2, 3, 3, 3]` using a set.
4. Convert `"250"` to a number and add 50 to it.
5. Use `type()` on `3`, `3.0`, `"3"` and `[3]` and see the differences.

Answers:
```python
c = ["Chennai", "Delhi", "Mumbai"]; c.append("Pune"); print(c[1])
s = {"name": "Asha", "age": 21, "marks": 88}; print(s["marks"])
print(set([1, 2, 2, 3, 3, 3]))
print(int("250") + 50)
for v in [3, 3.0, "3", [3]]: print(type(v))
```

Where to try code: open a Snowflake Notebook (Python cell), or any Python editor, and paste the examples.

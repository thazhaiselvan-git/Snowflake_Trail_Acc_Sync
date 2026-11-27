# Python Slicing and Reversing: Basics to Advanced

Syntax: **`seq[start:stop:step]`**

| Part | Meaning | Default |
|---|---|---|
| `start` | Where to begin (**included**) | `0` (or the end if step < 0) |
| `stop` | Where to end (**excluded**) | The end (or before the start if step < 0) |
| `step` | How far to jump; negative walks backwards | `1` |

---

## Level 1: Indexing (one character)

```python
w = "PYTHON"
#     P  Y  T  H  O  N
#     0  1  2  3  4  5     <- positive index
#    -6 -5 -4 -3 -2 -1     <- negative index (counts from the end)

print(w[0])    # 'P'
print(w[5])    # 'N'
print(w[-1])   # 'N'  (last character)
print(w[-2])   # 'O'
# w[6]         # IndexError: string index out of range
```

## Level 2: Basic slice `[start:stop]`

`start` is included and `stop` is excluded, so you get `stop - start` characters.

```python
print(w[1:4])   # 'YTH'  (indexes 1, 2, 3)
print(w[0:2])   # 'PY'
print(w[2:2])   # ''     (start == stop gives an empty string)
```

## Level 3: Leaving out start or stop

```python
print(w[:3])    # 'PYT'    from the beginning (first 3)
print(w[3:])    # 'HON'    to the end
print(w[:])     # 'PYTHON' the whole string (a copy)
```

`w[:n]` gives the first n characters and `w[n:]` gives everything after them. `w[:n] + w[n:] == w` is always true.

## Level 4: Negative indexes in slices

```python
print(w[-3:])    # 'HON'   last 3 characters
print(w[:-1])    # 'PYTHO' everything except the last
print(w[1:-1])   # 'YTHO'  drop the first and last
print(w[-4:-1])  # 'THO'
```

## Level 5: Step `[start:stop:step]`

```python
print(w[::2])    # 'PTO'   indexes 0, 2, 4
print(w[1::2])   # 'YHN'   indexes 1, 3, 5
print(w[::3])    # 'PH'    indexes 0, 3
```

## Level 6: Negative step (reversing)

```python
print(w[::-1])   # 'NOHTYP'  full reverse
print(w[::-2])   # 'NHY'     indexes 5, 3, 1
```

**Key rule:** with a negative step, the slice walks right to left, so the defaults flip. `start` defaults to the end, `stop` defaults to just before the beginning, and `start` must be greater than `stop`.

```python
print(w[4:1:-1])    # 'OHT'  indexes 4, 3, 2 (1 is excluded)
print(w[1:4:-1])    # ''     can't walk backwards from 1 to 4
print(w[-1:-4:-1])  # 'NOH'  last 3, reversed
print(w[3::-1])     # 'HTYP' from index 3 back to the start
print(w[:2:-1])     # 'NOH'  from the end back to index 3
```

## Level 7: Out of range values never raise an error

```python
print(w[2:100])   # 'THON' stop is clamped to the length
print(w[100:])    # ''
print(w[-100:2])  # 'PY'
# Indexing is different: w[100] raises IndexError
```

## Level 8: Slicing lists, which can also be changed

The same syntax works on lists, tuples and `range`. Lists are mutable, so you can also assign to a slice or delete one.

```python
nums = [1, 2, 3, 4, 5]
print(nums[1:4])      # [2, 3, 4]
print(nums[::-1])     # [5, 4, 3, 2, 1]  (a new list)
print(tuple("abc")[::-1])      # ('c', 'b', 'a')
print(list(range(10))[2:8:2])  # [2, 4, 6]

# Slice assignment (the new part can be a different length)
nums[1:3] = [20, 30, 40]
print(nums)           # [1, 20, 30, 40, 4, 5]

# Deleting a slice
del nums[::2]         # removes indexes 0, 2, 4
print(nums)           # [20, 40, 5]

# Assigning to a slice with a step needs the SAME length
# nums[::2] = [0]     # ValueError

# Strings can't be changed: w[0] = 'J' raises TypeError
w2 = "J" + w[1:]      # build a new string instead
print(w2)             # 'JYTHON'
```

## Level 9: A slice makes a shallow copy

```python
a = [[1], [2]]
b = a[:]              # new outer list
b.append([3])
print(a)              # [[1], [2]] (not affected)
b[0].append(9)
print(a)              # [[1, 9], [2]] (the inner lists are shared)
# For a full independent copy use copy.deepcopy(a)
```

## Level 10: `slice` objects

```python
first3 = slice(0, 3)
rev = slice(None, None, -1)
print(w[first3])                 # 'PYT'
print(w[rev])                    # 'NOHTYP'
print([10, 20, 30, 40][first3])  # [10, 20, 30]
```

Named slices are useful for fixed-width data, for example `ID = slice(0, 5)`.

## Level 11: Ways to reverse, compared

```python
nums = [1, 2, 3]

nums[::-1]               # new reversed list; nums is unchanged
list(reversed(nums))     # reversed() returns an iterator, so wrap it in list()
"".join(reversed(w))     # 'NOHTYP' (for strings)
nums.reverse()           # reverses IN PLACE and returns None
print(nums)              # [3, 2, 1]
```

| Method | Returns | Changes the original? |
|---|---|---|
| `x[::-1]` | New sequence | No |
| `reversed(x)` | Iterator (memory efficient) | No |
| `list.reverse()` | `None` | Yes (lists only) |

## Level 12: Interview problems

```python
t = "Snowflake Data Cloud"

# 1. Reverse the order of words
print(" ".join(t.split()[::-1]))             # 'Cloud Data Snowflake'

# 2. Reverse each word but keep the word order
print(" ".join(x[::-1] for x in t.split()))  # 'ekalfwonS ataD duolC'

# 3. Palindrome check that ignores case and punctuation
def is_pal(x):
    clean = "".join(c.lower() for c in x if c.isalnum())
    return clean == clean[::-1]
print(is_pal("Madam"))                           # True
print(is_pal("A man, a plan, a canal: Panama"))  # True

# 4. Rotate a list by k
nums, k = [1, 2, 3, 4, 5], 2
print(nums[k:] + nums[:k])     # left:  [3, 4, 5, 1, 2]
print(nums[-k:] + nums[:-k])   # right: [4, 5, 1, 2, 3]

# 5. Split a list into chunks of size n
data, n = list(range(1, 8)), 3
print([data[i:i+n] for i in range(0, len(data), n)])  # [[1, 2, 3], [4, 5, 6], [7]]

# 6. Is a number a palindrome?
print(str(12321) == str(12321)[::-1])  # True
```

---

## Summary

1. `stop` is **excluded**, so `x[a:b]` has `b - a` items.
2. Leaving out a value means "go as far as possible" in the direction the step points.
3. A negative step reverses direction, so `start` must be greater than `stop`.
4. `[::-1]` is the standard Python way to reverse.
5. A slice never raises an error, while an out-of-range index raises `IndexError`.
6. A slice always returns a **new** object (a shallow copy for lists).
